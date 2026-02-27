# k3s Vagrant Lab

Deterministic k3s lab on Vagrant VMs, including dedicated external etcd nodes and optional API load balancer.

## What this gives you
- Parameterized topology: `n` control planes and `m` workers.
- Dedicated external etcd tier (`etcd1..etcdN`, default `3`).
- Optional API LB node (`api-lb`) for stable multi-control-plane API endpoint.
- Incremental bring-up targets (`up-etcd`, `up-cp1`, `up-cps`, `up-workers`) for faster troubleshooting.
- Connectivity validation helpers for external etcd.

## Quick start
1. Copy defaults:
   ```bash
   cp config/cluster.env.example config/cluster.env
   ```
2. Tune `config/cluster.env` (for example `KUBE_CP_COUNT`, `KUBE_WORKER_COUNT`, `KUBE_ETCD_COUNT`, `KUBE_PROVIDER`).
3. Bring the cluster up:
   ```bash
   make up
   make kubeconfig
   make validate
   ```

By default, `make up` auto-runs `make destroy` if bring-up fails.  
Disable with:
```bash
make up AUTO_CLEANUP_ON_FAILURE=false
```

## Default topology
- `KUBE_CP_COUNT=3`
- `KUBE_WORKER_COUNT=5`
- `KUBE_ETCD_COUNT=3`
- `KUBE_PROVIDER=libvirt`
- `KUBE_API_LB_ENABLED=true` (effective only when `KUBE_CP_COUNT>1`)
- `KUBE_API_LB_IP=10.30.0.5`
- `KUBE_NETWORK_PREFIX=10.30.0`

Lean sizing defaults from `config/cluster.env.example`:
- `KUBE_CP_CPUS=1`, `KUBE_CP_MEMORY=1536`
- `KUBE_WORKER_CPUS=1`, `KUBE_WORKER_MEMORY=1536`

## External etcd
This lab uses dedicated etcd nodes (not embedded etcd inside control-plane nodes).  
Default topology:
```bash
make destroy
make up KUBE_ETCD_COUNT=3
```

You can validate etcd cluster endpoint/member/leader/peer connectivity with:
```bash
make etcd-connectivity
```

## Commands
- `make up`: bring up full topology (`api-lb` when applicable + etcd + control planes + workers).
- `make up-etcd`: bring up/provision only external etcd nodes, then wait for quorum.
- `make up-cp1`: bring up/provision first control-plane node.
- `make up-cps`: bring up/provision additional control-plane nodes (`cp2..cpN`).
- `make up-workers`: bring up/provision workers.
- `make up-node NODE=...`: bring up one node without provisioning.
- `make provision-node NODE=...`: provision one node.
- `make wait-server-api`: wait for k3s server API readiness gate.
- `make etcd-connectivity`: run external etcd connectivity checks.
- `make kubeconfig`: refresh `.cluster/admin.conf` from `cp1`.
- `make validate`: run cluster validation checks.
- `make destroy`: destroy VMs and local generated state.
- `make test-examples`: run example script self-tests.
- `make test`: run static checks plus example script self-tests.

## HA kubeconfig behavior
`make kubeconfig` always writes `.cluster/admin.conf` and rewrites the API endpoint:
- `https://<KUBE_API_LB_IP>:6443` when API LB is enabled and `KUBE_CP_COUNT>1`.
- `https://<KUBE_NETWORK_PREFIX>.11:6443` (cp1) otherwise.

Use:
```bash
KUBECONFIG="$PWD/.cluster/admin.conf" kubectl get nodes -o wide
```

## Incremental bring-up workflow
When debugging bootstrap issues, run stages manually:
```bash
make destroy
make up-etcd
make up-cp1
make up-cps
make up-workers
make kubeconfig
make validate
```

## Troubleshooting
If bring-up fails:
1. Retry fresh:
   ```bash
   make destroy
   make up
   ```
2. Inspect node status:
   ```bash
   vagrant status
   ```
3. Validate etcd separately:
   ```bash
   make etcd-connectivity
   ```
