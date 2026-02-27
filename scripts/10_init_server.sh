#!/usr/bin/env bash
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.30.6+k3s1}"
SERVER_IP="${SERVER_IP:-10.30.0.11}"
SERVER_ENDPOINT="${SERVER_ENDPOINT:-https://${SERVER_IP}:6443}"
EXTERNAL_ETCD_ENDPOINTS="${EXTERNAL_ETCD_ENDPOINTS:-http://10.30.0.21:2379,http://10.30.0.22:2379,http://10.30.0.23:2379}"
K3S_CLUSTER_TOKEN="${K3S_CLUSTER_TOKEN:-k3s-vagrant-shared-token}"

mkdir -p /vagrant/.cluster

if systemctl is-active --quiet k3s; then
  echo "k3s server already active"
else
  endpoint_host="${SERVER_ENDPOINT#https://}"
  endpoint_host="${endpoint_host%:6443}"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" K3S_TOKEN="${K3S_CLUSTER_TOKEN}" \
    INSTALL_K3S_EXEC="server --write-kubeconfig-mode 0644 --node-ip ${SERVER_IP} --tls-san ${SERVER_IP} --tls-san ${endpoint_host} --datastore-endpoint=${EXTERNAL_ETCD_ENDPOINTS}" \
    sh -
fi

systemctl enable k3s
systemctl restart k3s

for _ in $(seq 1 120); do
  if kubectl get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
  echo "Timed out waiting for k3s API readiness" >&2
  exit 1
fi

cp /etc/rancher/k3s/k3s.yaml /vagrant/.cluster/admin.conf
chmod 600 /vagrant/.cluster/admin.conf
cp /var/lib/rancher/k3s/server/node-token /vagrant/.cluster/node-token
chmod 600 /vagrant/.cluster/node-token
printf '%s\n' "${K3S_CLUSTER_TOKEN}" >/vagrant/.cluster/k3s-token
chmod 600 /vagrant/.cluster/k3s-token
touch /vagrant/.cluster/ready
