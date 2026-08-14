#!/usr/bin/env bash
set -euo pipefail

# Helm chart e2e test.
#
# Creates a throwaway kind cluster, installs the chart under a few configurations, and verifies runtime behavior against /global/health.
# Requires: kind, kubectl, helm on PATH.
#
# Env vars:
#   CHART_DIR   Path to the chart directory (default: chart)
#   NAMESPACE   Kubernetes namespace for the tests (default: opencode)
#   CLUSTER     Kind cluster name (default: opencode-e2e)
#   LOCAL_PORT  Local port for port-forwarding (default: 8080)
#   TIMEOUT     Pod Ready timeout in seconds (default: 180)
#   RETRIES     Health-check retries (default: 30)

CHART_DIR="${CHART_DIR:-chart}"
NAMESPACE="${NAMESPACE:-opencode}"
CLUSTER="${CLUSTER:-opencode-e2e}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
TIMEOUT="${TIMEOUT:-180}"
RETRIES="${RETRIES:-30}"

RELEASE="opencode"
FULLNAME="${RELEASE}"
HEALTH_URL="http://127.0.0.1:${LOCAL_PORT}/global/health"
PORT_FORWARD_PID=""

log() { printf '==> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

stop_port_forward() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    PORT_FORWARD_PID=""
  fi
}

cleanup() {
  stop_port_forward
  log "Deleting kind cluster ${CLUSTER}"
  kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

install_and_wait() {
  log "Installing release ${RELEASE}"
  helm install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    "$@"

  log "Waiting for pods to become Ready (${TIMEOUT}s)"
  local ready=""
  local deadline=$((SECONDS + TIMEOUT))
  while (( SECONDS < deadline )); do
    if kubectl --namespace "${NAMESPACE}" wait \
      --for=condition=Ready \
      --timeout=2s \
      pod -l app.kubernetes.io/instance=${RELEASE} >/dev/null 2>&1; then
      ready="yes"
      break
    fi
    sleep 2
  done
  if [[ -z "${ready}" ]]; then
    log "Pod wait failed. Debugging info:"
    kubectl --namespace "${NAMESPACE}" get pods -o wide
    kubectl --namespace "${NAMESPACE}" get events --sort-by='.lastTimestamp' | tail -20
    kubectl --namespace "${NAMESPACE}" describe pod -l app.kubernetes.io/instance=${RELEASE} || true
    log "Container logs:"
    kubectl --namespace "${NAMESPACE}" logs -l app.kubernetes.io/instance=${RELEASE} --tail=50 || true
    fail "Pods did not become Ready"
  fi

  log "Port-forwarding svc/${FULLNAME} ${LOCAL_PORT}:80"
  kubectl --namespace "${NAMESPACE}" port-forward \
    "svc/${FULLNAME}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!
}

assert_health() {
  local expect="$1"
  local url="$2"
  shift 2
  local code=""

  log "Expecting HTTP ${expect} from ${url}"
  for _ in $(seq 1 "${RETRIES}"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$@" "${url}" || true)
    if [[ "${code}" == "${expect}" ]]; then
      log "Health check passed (HTTP ${code})"
      return 0
    fi
    sleep 1
  done
  fail "expected HTTP ${expect} from ${url} but got ${code:-no response}"
}

uninstall() {
  stop_port_forward
  log "Uninstalling release ${RELEASE}"
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" >/dev/null 2>&1 || true
}

main() {
  log "Creating kind cluster ${CLUSTER}"
  kind create cluster --name "${CLUSTER}"

  # Scenario 1: default values.
  install_and_wait
  assert_health 200 "${HEALTH_URL}"
  uninstall

  # TODO: Re-enable once upstream opencode-server exempts /global/health from auth.
  # Scenario 2: basic auth enabled. The root endpoint rejects
  # unauthenticated requests (401) and accepts authenticated ones (200).
  # install_and_wait \
  #   --set auth.basic.enabled=true \
  #   --set auth.basic.password=e2e-secret
  # assert_health 401 "http://127.0.0.1:${LOCAL_PORT}/"
  # assert_health 200 "http://127.0.0.1:${LOCAL_PORT}/" -u "${RELEASE}:e2e-secret"
  # uninstall

  # Scenario 3: custom config with a different server port. Verify the
  # ConfigMap is created and the health endpoint answers on the new port.
  install_and_wait \
    --set config.enabled=true \
    --set 'config.content.server.port=8080' \
    --set 'config.content.server.hostname=0.0.0.0'
  log "Verifying ConfigMap ${FULLNAME}-config exists"
  kubectl --namespace "${NAMESPACE}" get configmap "${FULLNAME}-config"
  assert_health 200 "${HEALTH_URL}"
  uninstall

  log "All e2e scenarios passed"
}

main "$@"
