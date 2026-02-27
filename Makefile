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

export
VAGRANT_RUN := ./scripts/vagrant_retry.sh vagrant

.PHONY: help
help:
	@echo "Commands:"
	@echo "- up\t\t: bring up k3s cluster (api-lb + etcd + cp + workers)"
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
	set -e; \
	for i in $$(seq 1 "$${KUBE_ETCD_COUNT:-3}"); do \
		$(VAGRANT_RUN) up "etcd$${i}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
		$(VAGRANT_RUN) provision "etcd$${i}"; \
	done
	./scripts/wait_external_etcd_cluster.sh

.PHONY: up-cp1
up-cp1:
	$(VAGRANT_RUN) up cp1 --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision
	$(VAGRANT_RUN) provision cp1
	./scripts/wait_server_api_ready.sh

.PHONY: up-cps
up-cps:
	@if [ "$${KUBE_CP_COUNT:-1}" -le 1 ]; then echo "KUBE_CP_COUNT<=1, no additional servers."; exit 0; fi
	set -e; \
	for i in $$(seq 2 "$${KUBE_CP_COUNT}"); do \
		./scripts/wait_external_etcd_cluster.sh; \
		./scripts/wait_server_api_ready.sh; \
		$(VAGRANT_RUN) up "cp$${i}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
		$(VAGRANT_RUN) provision "cp$${i}"; \
		./scripts/wait_server_api_ready.sh; \
	done

.PHONY: up-workers
up-workers:
	@if [ "$${KUBE_WORKER_COUNT:-0}" -le 0 ]; then echo "No workers configured (KUBE_WORKER_COUNT=0)."; exit 0; fi
	set -e; \
	for i in $$(seq 1 "$${KUBE_WORKER_COUNT}"); do \
		$(VAGRANT_RUN) up "worker$${i}" --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; \
		$(VAGRANT_RUN) provision "worker$${i}"; \
	done

.PHONY: etcd-connectivity
etcd-connectivity:
	./examples/check_etcd_connectivity.sh

.PHONY: wait-server-api
wait-server-api:
	./scripts/wait_server_api_ready.sh

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
	@effective_api_lb="false"; \
	if [ "$${KUBE_API_LB_ENABLED:-true}" = "true" ] && [ "$${KUBE_CP_COUNT:-1}" -gt 1 ]; then effective_api_lb="true"; fi; \
	echo "Topology: control-planes=$${KUBE_CP_COUNT:-3} workers=$${KUBE_WORKER_COUNT:-5} external-etcd=$${KUBE_ETCD_COUNT:-3} api-lb=$${effective_api_lb}"
	if [ "$${KUBE_API_LB_ENABLED:-true}" = "true" ] && [ "$${KUBE_CP_COUNT:-1}" -gt 1 ]; then $(VAGRANT_RUN) up api-lb --provider "$${KUBE_PROVIDER:-libvirt}" --no-provision; fi
	if [ "$${KUBE_API_LB_ENABLED:-true}" = "true" ] && [ "$${KUBE_CP_COUNT:-1}" -gt 1 ]; then $(VAGRANT_RUN) provision api-lb; fi
	$(MAKE) up-etcd
	$(MAKE) up-cp1
	$(MAKE) up-cps
	$(MAKE) up-workers
	$(MAKE) kubeconfig

.PHONY: kubeconfig
kubeconfig:
	mkdir -p .cluster
	$(VAGRANT_RUN) ssh cp1 -c 'sudo cat /etc/rancher/k3s/k3s.yaml' > .cluster/admin.conf
	@api="$${KUBE_NETWORK_PREFIX:-10.30.0}.11"; \
	if [ "$${KUBE_API_LB_ENABLED:-true}" = "true" ] && [ "$${KUBE_CP_COUNT:-1}" -gt 1 ]; then api="$${KUBE_API_LB_IP:-$${KUBE_NETWORK_PREFIX:-10.30.0}.5}"; fi; \
	sed -i "s#https://127.0.0.1:6443#https://$${api}:6443#g" .cluster/admin.conf
	chmod 600 .cluster/admin.conf

.PHONY: validate
validate:
	./scripts/validate_cluster.sh

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
