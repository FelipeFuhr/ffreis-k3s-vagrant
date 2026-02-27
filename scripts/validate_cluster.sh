#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_FILE="${KUBECONFIG_FILE:-.cluster/admin.conf}"
CP_COUNT="${KUBE_CP_COUNT:-1}"
WORKER_COUNT="${KUBE_WORKER_COUNT:-0}"
expected_total=$((CP_COUNT + WORKER_COUNT))

if [[ ! -f "${KUBECONFIG_FILE}" ]]; then
  echo "Missing ${KUBECONFIG_FILE}. Run make kubeconfig first." >&2
  exit 1
fi

ready_nodes="$(
  KUBECONFIG="${KUBECONFIG_FILE}" kubectl get nodes --no-headers \
    | awk '$2=="Ready" {count++} END {print count+0}'
)"

if [[ "${ready_nodes}" -lt "${expected_total}" ]]; then
  echo "Expected ${expected_total} Ready nodes, got ${ready_nodes}" >&2
  KUBECONFIG="${KUBECONFIG_FILE}" kubectl get nodes -o wide || true
  exit 1
fi

KUBECONFIG="${KUBECONFIG_FILE}" kubectl get pods -A >/dev/null
echo "k3s cluster validation passed"
