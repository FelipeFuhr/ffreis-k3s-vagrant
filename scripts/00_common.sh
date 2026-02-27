#!/usr/bin/env bash
set -euo pipefail

NODE_ROLE="${NODE_ROLE:-}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y -o APT::Update::Error-Mode=any
apt-get install -y curl ca-certificates tar

if [[ "${NODE_ROLE}" == "api-lb" ]]; then
  exit 0
fi

swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

modprobe br_netfilter || true
cat >/etc/sysctl.d/99-k3s.conf <<CFG
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
CFG
sysctl --system >/dev/null
