#!/usr/bin/env bash
set -euo pipefail

ETCD_NAME="${ETCD_NAME:?ETCD_NAME is required}"
ETCD_IP="${ETCD_IP:?ETCD_IP is required}"
ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER:?ETCD_INITIAL_CLUSTER is required}"
ETCD_VERSION="${ETCD_VERSION:-3.5.15}"

retry_download() {
  local url="$1"
  local out_file="$2"
  local attempts="${3:-8}"
  local n=1
  until curl -fL --connect-timeout 15 --max-time 180 --retry 5 --retry-delay 2 --retry-all-errors "${url}" -o "${out_file}"; do
    if [[ "${n}" -ge "${attempts}" ]]; then
      return 1
    fi
    n=$((n + 1))
    sleep 4
  done
}

export DEBIAN_FRONTEND=noninteractive
apt-get update -y -o APT::Update::Error-Mode=any
apt-get install -y curl tar ca-certificates

if ! id -u etcd >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/etcd --shell /usr/sbin/nologin etcd
fi

installed_version="$(etcd --version 2>/dev/null | awk '/^etcd Version:/ {print $3}' || true)"
if [[ "${installed_version}" != "${ETCD_VERSION}" || ! -x /usr/local/bin/etcdctl ]]; then
  tmp_dir="$(mktemp -d)"
  archive="etcd-v${ETCD_VERSION}-linux-amd64.tar.gz"
  download_url="https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/${archive}"
  retry_download "${download_url}" "${tmp_dir}/${archive}" 8
  tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}"
  install -m 0755 "${tmp_dir}/etcd-v${ETCD_VERSION}-linux-amd64/etcd" /usr/local/bin/etcd
  install -m 0755 "${tmp_dir}/etcd-v${ETCD_VERSION}-linux-amd64/etcdctl" /usr/local/bin/etcdctl
  rm -rf "${tmp_dir}"
fi

systemctl stop etcd >/dev/null 2>&1 || true
rm -rf /var/lib/etcd/default
install -d -m 0700 -o etcd -g etcd /var/lib/etcd/default

cat >/etc/systemd/system/etcd.service <<CFG
[Unit]
Description=etcd key-value store
Documentation=https://etcd.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=etcd
Group=etcd
ExecStart=/usr/local/bin/etcd \
  --name=${ETCD_NAME} \
  --data-dir=/var/lib/etcd/default \
  --listen-client-urls=http://${ETCD_IP}:2379,http://127.0.0.1:2379 \
  --advertise-client-urls=http://${ETCD_IP}:2379 \
  --listen-peer-urls=http://${ETCD_IP}:2380 \
  --initial-advertise-peer-urls=http://${ETCD_IP}:2380 \
  --initial-cluster=${ETCD_INITIAL_CLUSTER} \
  --initial-cluster-state=new \
  --initial-cluster-token=k3s-vagrant-external-etcd
Restart=always
RestartSec=5
TimeoutStartSec=120
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
CFG

systemctl daemon-reload
systemctl enable etcd
chown -R etcd:etcd /var/lib/etcd
systemctl restart etcd
