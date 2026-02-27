#!/usr/bin/env bash
set -euo pipefail

MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-480}"
SLEEP_SECONDS="${SLEEP_SECONDS:-5}"
WAIT_REPORT_INTERVAL_SECONDS="${WAIT_REPORT_INTERVAL_SECONDS:-60}"
KUBE_NETWORK_PREFIX="${KUBE_NETWORK_PREFIX:-10.30.0}"
KUBE_API_LB_ENABLED="${KUBE_API_LB_ENABLED:-true}"
KUBE_CP_COUNT="${KUBE_CP_COUNT:-1}"
KUBE_API_LB_IP="${KUBE_API_LB_IP:-${KUBE_NETWORK_PREFIX}.5}"
CP1_IP="${CP1_IP:-${KUBE_NETWORK_PREFIX}.11}"

vagrant_cmd() {
  ./scripts/vagrant_retry.sh vagrant "$@"
}

remote_state() {
  vagrant_cmd ssh cp1 -c "systemctl is-active k3s || true" 2>/dev/null | tr -d '\r'
}

dump_k3s_diagnostics() {
  echo "---- cp1: systemctl status k3s ----" >&2
  vagrant_cmd ssh cp1 -c "sudo systemctl status --no-pager --full k3s || true" >&2 || true
  echo "---- cp1: journalctl -u k3s (last 120 lines) ----" >&2
  vagrant_cmd ssh cp1 -c "sudo journalctl -u k3s --no-pager -n 120 || true" >&2 || true
}

log_wait_progress() {
  local label="$1"
  local waited="$2"
  local timeout="$3"
  local report_interval="$4"
  local step total_steps

  total_steps=$(((timeout + report_interval - 1) / report_interval))
  if [[ "${total_steps}" -lt 1 ]]; then
    total_steps=1
  fi

  step=$((waited / report_interval + 1))
  if [[ "${step}" -gt "${total_steps}" ]]; then
    step="${total_steps}"
  fi

  echo "${label} (${step}/${total_steps}, ${waited}s/${timeout}s elapsed)"
}

waited=0
report_interval="${WAIT_REPORT_INTERVAL_SECONDS}"
if [[ "${report_interval}" -lt "${SLEEP_SECONDS}" ]]; then
  report_interval="${SLEEP_SECONDS}"
fi

while true; do
  cp1_local_ready=0
  cp1_advertised_ready=0
  lb_ready=0
  lb_required=0

  k3s_state="$(remote_state)"
  if [[ "${k3s_state}" == "failed" ]]; then
    echo "cp1 k3s service is in failed state; aborting API wait." >&2
    dump_k3s_diagnostics
    exit 1
  fi

  if vagrant_cmd ssh cp1 -c "curl -sk https://127.0.0.1:6443/readyz >/dev/null"; then
    cp1_local_ready=1
  fi

  if vagrant_cmd ssh cp1 -c "curl -sk https://${CP1_IP}:6443/readyz >/dev/null"; then
    cp1_advertised_ready=1
  fi

  if [[ "${KUBE_API_LB_ENABLED}" == "true" && "${KUBE_CP_COUNT}" -gt 1 ]]; then
    lb_required=1
    if vagrant_cmd ssh cp1 -c "curl -sk https://${KUBE_API_LB_IP}:6443/readyz >/dev/null"; then
      lb_ready=1
    fi
  fi

  if [[ "${cp1_local_ready}" -eq 1 && "${cp1_advertised_ready}" -eq 1 ]]; then
    if [[ "${lb_required}" -eq 0 || "${lb_ready}" -eq 1 ]]; then
      if [[ "${waited}" -gt 0 ]]; then
        echo "k3s API readiness gate passed after ${waited}s"
      fi
      exit 0
    fi
  fi

  if (( waited == 0 || waited % report_interval == 0 )); then
    log_wait_progress "Waiting for k3s API readiness (k3s-state=${k3s_state:-unknown}, cp1-local=${cp1_local_ready}, cp1-advertised=${cp1_advertised_ready}, lb-required=${lb_required}, lb=${lb_ready})" "${waited}" "${MAX_WAIT_SECONDS}" "${report_interval}"
  fi

  if [[ "${waited}" -ge "${MAX_WAIT_SECONDS}" ]]; then
    echo "Timed out waiting for k3s API readiness (cp1=${CP1_IP}, lb=${KUBE_API_LB_IP})" >&2
    dump_k3s_diagnostics
    exit 1
  fi

  sleep "${SLEEP_SECONDS}"
  waited=$((waited + SLEEP_SECONDS))
done
