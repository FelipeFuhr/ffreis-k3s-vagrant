# Agent Context

**This repo:** `ffreis-k3s-vagrant` — deterministic k3s cluster on Vagrant VMs with
dedicated external etcd. Lightweight alternative to kubeadm for lab/CI use.

## Non-obvious facts

- **k3s, not kubeadm.** k3s bundles Kubernetes into a single binary. Some standard
  `kubectl` behaviors differ slightly from full kubeadm installations.

- **External etcd by default** — not embedded. This scales control planes independently
  but requires etcd VMs to be healthy before any control plane can start. Always
  bring up etcd first: `make up-etcd`.

- **Incremental bring-up order matters:** `up-etcd` → `up-cp1` → `up-cps` → `up-workers`.
  Skipping steps causes join failures.

- **Auto-cleanup on failure** — the Makefile destroys the cluster on failure unless
  `AUTO_CLEANUP_ON_FAILURE=false`. Set this when debugging provisioning failures.

- **Topology defined in `config/cluster.env`** (copy from `cluster.env.example`).
  This file is gitignored. Do not hardcode topology in Vagrantfiles.

- **Provider: libvirt preferred**, virtualbox fallback. Libvirt requires `vagrant-libvirt`
  plugin; check `make doctor`.

## Structure

```
config/cluster.env      ← topology parameters (gitignored)
Makefile                ← orchestration commands
.cluster/               ← generated state (kubeconfig, logs)
scripts/                ← etcd connectivity checks, validation
```

## Build/run

```bash
cp config/cluster.env.example config/cluster.env   # edit as needed
make up          # brings up full cluster
make validate    # verify all nodes ready
make kubeconfig  # outputs kubeconfig to .cluster/admin.conf
make destroy
```

## Relation to other local-dev repos

Lighter-weight alternative to `ffreis-k8s-vagrant` (kubeadm, more features).
Use k3s for fast iteration; use kubeadm-based repos for production-like testing.
