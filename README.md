# k3s Vagrant Lab

Lightweight Kubernetes lab using k3s, with topology defaults aligned to the kubeadm stack.

## Quick start

```bash
cp config/cluster.env.example config/cluster.env
make up
make kubeconfig
make validate
```

By default, `make up` auto-runs `make destroy` on failure.
Disable with: `make up AUTO_CLEANUP_ON_FAILURE=false`.

## Default topology

- `KUBE_CP_COUNT=3`
- `KUBE_WORKER_COUNT=5`
- `KUBE_ETCD_COUNT=3` (dedicated external etcd nodes)
- `KUBE_API_LB_ENABLED=true` (enabled when control planes >1)
- Lean sizing defaults (as set in `config/cluster.env.example`):
- `KUBE_CP_CPUS=1`, `KUBE_CP_MEMORY=1536`
- `KUBE_WORKER_CPUS=1`, `KUBE_WORKER_MEMORY=1536`

## Useful checks

```bash
make etcd-connectivity
```
