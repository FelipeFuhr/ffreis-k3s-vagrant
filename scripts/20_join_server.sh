#!/usr/bin/env bash
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.30.6+k3s1}"
SERVER_IP="${SERVER_IP:-10.30.0.11}"
SERVER_ENDPOINT="${SERVER_ENDPOINT:-https://${SERVER_IP}:6443}"
EXTERNAL_ETCD_ENDPOINTS="${EXTERNAL_ETCD_ENDPOINTS:-http://10.30.0.21:2379,http://10.30.0.22:2379,http://10.30.0.23:2379}"
K3S_CLUSTER_TOKEN="${K3S_CLUSTER_TOKEN:-k3s-vagrant-shared-token}"
CP1_ENDPOINT="https://${SERVER_IP}:6443"

if systemctl is-active --quiet k3s; then
  echo "k3s server already active on $(hostname -s)"
  exit 0
fi

for _ in $(seq 1 300); do
  if curl -sk "${SERVER_ENDPOINT}/readyz" >/dev/null 2>&1 \
    || curl -sk "${CP1_ENDPOINT}/readyz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -sk "${SERVER_ENDPOINT}/readyz" >/dev/null 2>&1 \
  && ! curl -sk "${CP1_ENDPOINT}/readyz" >/dev/null 2>&1; then
  echo "Timed out waiting for server API readiness at ${SERVER_ENDPOINT} (fallback ${CP1_ENDPOINT})" >&2
  exit 1
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" K3S_TOKEN="${K3S_CLUSTER_TOKEN}" K3S_URL="${SERVER_ENDPOINT}" \
  INSTALL_K3S_EXEC="server --server ${SERVER_ENDPOINT} --node-ip ${SERVER_IP} --datastore-endpoint=${EXTERNAL_ETCD_ENDPOINTS}" \
  sh -

systemctl enable k3s
systemctl restart k3s
