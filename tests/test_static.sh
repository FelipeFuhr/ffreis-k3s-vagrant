#!/usr/bin/env bash
set -euo pipefail

ruby -c Vagrantfile >/dev/null

for script in scripts/*.sh; do
  bash -n "${script}"
done

if compgen -G "examples/*.sh" >/dev/null; then
  for script in examples/*.sh; do
    bash -n "${script}"
  done
fi

if [[ ! -f config/cluster.env.example ]]; then
  echo "Missing config/cluster.env.example"
  exit 1
fi

required_keys=(
  KUBE_CP_COUNT
  KUBE_WORKER_COUNT
  KUBE_ETCD_COUNT
  KUBE_PROVIDER
  KUBE_API_LB_ENABLED
  KUBE_API_LB_IP
  KUBE_NETWORK_PREFIX
  K3S_VERSION
  K3S_CLUSTER_TOKEN
)

for key in "${required_keys[@]}"; do
  if ! grep -q "^${key}=" config/cluster.env.example; then
    echo "Missing required key in k3s config: ${key}"
    exit 1
  fi
done

echo "k3s static checks passed"
