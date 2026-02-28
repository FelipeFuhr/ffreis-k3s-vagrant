.DEFAULT_GOAL := help

-include config/cluster.env

KUBE_CP_COUNT ?= 3
KUBE_WORKER_COUNT ?= 5
KUBE_ETCD_COUNT ?= 3
KUBE_PROVIDER ?= libvirt
KUBE_API_LB_ENABLED ?= true
KUBE_API_LB_IP ?= 10.30.0.5
KUBE_NETWORK_PREFIX ?= 10.30.0
K3S_CLUSTER_TOKEN ?= k3s-vagrant-shared-token
AUTO_CLEANUP_ON_FAILURE ?= true
NODE_INVENTORY_FILE ?=

export
VAGRANT_RUN := ./scripts/vagrant_retry.sh vagrant
LIST_NODES := ./scripts/list_nodes.sh
GET_NODE_IP := ./scripts/get_node_ip.sh

.PHONY: help
help:
	@echo "Commands:"
	@echo "- up\t\t: bring up k3s cluster (api-lb + etcd + cp + workers)"
	@echo "- validate-inventory NODE_INVENTORY_FILE=... : validate inventory file contract"
	@echo "- up-etcd\t: bring up/provision external etcd tier only"
	@echo "- up-cp1\t\t: bring up/provision first k3s server"
	@echo "- up-cps\t\t: bring up/provision additional k3s servers (cp2..cpN)"
	@echo "- up-workers\t: bring up/provision workers"
	@echo "- up-node NODE=name\t: bring up one node without provision"
	@echo "- provision-node NODE=name\t: provision one node"
	@echo "- etcd-connectivity\t: check external etcd health and peer connectivity"
	@echo "- wait-server-api\t: wait for cp1/LB API ready gate"
	@echo "- kubeconfig\t: refresh .cluster/admin.conf from cp1"
	@echo "- validate\t: validate node readiness"
	@echo "- destroy\t: destroy k3s nodes and local state"
	@echo "- up auto-cleans on failure by default (AUTO_CLEANUP_ON_FAILURE=true|false)"
	@echo "- test-examples\t: run example script self-tests"
	@echo "- test\t\t: static checks"

.PHONY: up-node
up-node:
	@if [ -z "$(NODE)" ]; then echo "Usage: make up-node NODE=cp1|cp2|worker1|etcd1|api-lb"; exit 1; fi
	$(VAGRANT_RUN) up "$(NODE)" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision

.PHONY: provision-node
provision-node:
	@if [ -z "$(NODE)" ]; then echo "Usage: make provision-node NODE=cp1|cp2|worker1|etcd1|api-lb"; exit 1; fi
	$(VAGRANT_RUN) provision "$(NODE)"

.PHONY: up-etcd
up-etcd:
	@etcd_nodes="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_ETCD_COUNT='$(KUBE_ETCD_COUNT)' $(LIST_NODES) etcd)"; \
	if [ -z "$${etcd_nodes}" ]; then echo "No etcd nodes resolved."; exit 1; fi; \
	set -e; \
	for node in $${etcd_nodes}; do \
		$(VAGRANT_RUN) up "$${node}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
		$(VAGRANT_RUN) provision "$${node}"; \
	done
	@primary_etcd="$$(printf '%s\n' "$${etcd_nodes}" | head -n1)"; \
	PRIMARY_ETCD_NAME="$${primary_etcd}" ./scripts/wait_external_etcd_cluster.sh

.PHONY: up-cp1
up-cp1:
	@primary_cp="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_CP_COUNT='$(KUBE_CP_COUNT)' $(LIST_NODES) control-plane | head -n1)"; \
	if [ -z "$${primary_cp}" ]; then echo "No control-plane nodes resolved."; exit 1; fi; \
	cp_ip="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_NETWORK_PREFIX='$(KUBE_NETWORK_PREFIX)' KUBE_API_LB_IP='$(KUBE_API_LB_IP)' $(GET_NODE_IP) "$${primary_cp}")"; \
	$(VAGRANT_RUN) up "$${primary_cp}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
	$(VAGRANT_RUN) provision "$${primary_cp}"; \
	PRIMARY_CP_NAME="$${primary_cp}" CP1_IP="$${cp_ip}" ./scripts/wait_server_api_ready.sh

.PHONY: up-cps
up-cps:
	@cp_nodes="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_CP_COUNT='$(KUBE_CP_COUNT)' $(LIST_NODES) control-plane)"; \
	cp_count="$$(printf '%s\n' "$${cp_nodes}" | sed '/^$$/d' | wc -l | tr -d ' ')"; \
	if [ "$${cp_count}" -le 1 ]; then echo "Only one control-plane resolved; no additional servers."; exit 0; fi; \
	primary_cp="$$(printf '%s\n' "$${cp_nodes}" | head -n1)"; \
	cp_ip="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_NETWORK_PREFIX='$(KUBE_NETWORK_PREFIX)' KUBE_API_LB_IP='$(KUBE_API_LB_IP)' $(GET_NODE_IP) "$${primary_cp}")"; \
	etcd_nodes="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_ETCD_COUNT='$(KUBE_ETCD_COUNT)' $(LIST_NODES) etcd)"; \
	primary_etcd="$$(printf '%s\n' "$${etcd_nodes}" | head -n1)"; \
	set -e; \
	printf '%s\n' "$${cp_nodes}" | tail -n +2 | while read -r node; do \
		PRIMARY_ETCD_NAME="$${primary_etcd}" ./scripts/wait_external_etcd_cluster.sh; \
		PRIMARY_CP_NAME="$${primary_cp}" CP1_IP="$${cp_ip}" ./scripts/wait_server_api_ready.sh; \
		$(VAGRANT_RUN) up "$${node}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
		$(VAGRANT_RUN) provision "$${node}"; \
		PRIMARY_CP_NAME="$${primary_cp}" CP1_IP="$${cp_ip}" ./scripts/wait_server_api_ready.sh; \
	done

.PHONY: up-workers
up-workers:
	@worker_nodes="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_WORKER_COUNT='$(KUBE_WORKER_COUNT)' $(LIST_NODES) worker)"; \
	if [ -z "$${worker_nodes}" ]; then echo "No workers resolved."; exit 0; fi; \
	set -e; \
	for node in $${worker_nodes}; do \
		$(VAGRANT_RUN) up "$${node}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
		$(VAGRANT_RUN) provision "$${node}"; \
	done

.PHONY: etcd-connectivity
etcd-connectivity:
	./examples/check_etcd_connectivity.sh

.PHONY: wait-server-api
wait-server-api:
	@primary_cp="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_CP_COUNT='$(KUBE_CP_COUNT)' $(LIST_NODES) control-plane | head -n1)"; \
	cp_ip="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_NETWORK_PREFIX='$(KUBE_NETWORK_PREFIX)' KUBE_API_LB_IP='$(KUBE_API_LB_IP)' $(GET_NODE_IP) "$${primary_cp}")"; \
	PRIMARY_CP_NAME="$${primary_cp}" CP1_IP="$${cp_ip}" ./scripts/wait_server_api_ready.sh

.PHONY: up
up:
	@set +e; \
	$(MAKE) up-core; \
	status=$$?; \
	if [ $$status -ne 0 ] && [ "$(AUTO_CLEANUP_ON_FAILURE)" = "true" ]; then \
		echo "k3s bring-up failed; running automatic cleanup (make destroy)"; \
		$(MAKE) destroy || true; \
	fi; \
	exit $$status

.PHONY: up-core
up-core:
	find .vagrant -type f -name '*.lock' -delete >/dev/null 2>&1 || true
	mkdir -p .cluster
	rm -f .cluster/failed .cluster/ready
	@cp_count="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_CP_COUNT='$(KUBE_CP_COUNT)' $(LIST_NODES) control-plane | sed '/^$$/d' | wc -l | tr -d ' ')"; \
	worker_count="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_WORKER_COUNT='$(KUBE_WORKER_COUNT)' $(LIST_NODES) worker | sed '/^$$/d' | wc -l | tr -d ' ')"; \
	etcd_count="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_ETCD_COUNT='$(KUBE_ETCD_COUNT)' $(LIST_NODES) etcd | sed '/^$$/d' | wc -l | tr -d ' ')"; \
	api_lb_node="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_CP_COUNT='$(KUBE_CP_COUNT)' KUBE_API_LB_ENABLED='$(KUBE_API_LB_ENABLED)' $(LIST_NODES) api-lb | head -n1)"; \
	effective_api_lb="false"; \
	if [ -n "$${api_lb_node}" ]; then effective_api_lb="true"; fi; \
	echo "Topology: control-planes=$${cp_count} workers=$${worker_count} external-etcd=$${etcd_count} api-lb=$${effective_api_lb}"; \
	if [ -n "$${api_lb_node}" ]; then $(VAGRANT_RUN) up "$${api_lb_node}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; fi; \
	if [ -n "$${api_lb_node}" ]; then $(VAGRANT_RUN) provision "$${api_lb_node}"; fi
	$(MAKE) up-etcd
	$(MAKE) up-cp1
	$(MAKE) up-cps
	$(MAKE) up-workers
	$(MAKE) kubeconfig

.PHONY: kubeconfig
kubeconfig:
	mkdir -p .cluster
	@primary_cp="$$(NODE_INVENTORY_FILE='$(NODE_INVENTORY_FILE)' KUBE_CP_COUNT='$(KUBE_CP_COUNT)' $(LIST_NODES) control-plane | head -n1)"; \
	$(VAGRANT_RUN) ssh "$${primary_cp}" -c 'sudo cat /etc/rancher/k3s/k3s.yaml' > .cluster/admin.conf
	@api="$${KUBE_NETWORK_PREFIX:-10.30.0}.11"; \
	if [ "$${KUBE_API_LB_ENABLED:-true}" = "true" ] && [ "$${KUBE_CP_COUNT:-1}" -gt 1 ]; then api="$${KUBE_API_LB_IP:-$${KUBE_NETWORK_PREFIX:-10.30.0}.5}"; fi; \
	sed -i "s#https://127.0.0.1:6443#https://$${api}:6443#g" .cluster/admin.conf
	chmod 600 .cluster/admin.conf
	@echo "Kubeconfig refreshed at .cluster/admin.conf"
	@echo "To run, point kubectl by running:"
	@echo "  KUBECONFIG=\$$PWD/.cluster/admin.conf kubectl get nodes -o wide"
	@echo "Optional shell setup for less verbose commands:"
	@echo "  export KUBECONFIG=\$$PWD/.cluster/admin.conf"
	@echo "  alias k='kubectl'"
	@echo "  k get pods -A"

.PHONY: validate
validate:
	./scripts/validate_cluster.sh

.PHONY: validate-inventory
validate-inventory:
	@if [ -z "$(NODE_INVENTORY_FILE)" ]; then echo "NODE_INVENTORY_FILE is required"; exit 1; fi
	@./scripts/load_node_inventory.py "$(NODE_INVENTORY_FILE)" >/dev/null
	@echo "Inventory file is valid: $(NODE_INVENTORY_FILE)"

.PHONY: destroy
destroy:
	find .vagrant -type f -name '*.lock' -delete >/dev/null 2>&1 || true
	$(VAGRANT_RUN) destroy -f api-lb || true
	$(VAGRANT_RUN) destroy -f || true
	rm -rf .cluster .vagrant .vagrant-nodes.json

.PHONY: test
test:
	./tests/test_static.sh
	$(MAKE) test-examples

.PHONY: test-examples
test-examples:
	./examples/check_etcd_connectivity.sh --self-test success >/dev/null
	@if ./examples/check_etcd_connectivity.sh --self-test failure >/dev/null 2>&1; then \
		echo "Expected --self-test failure to return non-zero"; \
		exit 1; \
	fi
