#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE_PLATFORM="engineering-platform"
NAMESPACE_KEYCLOAK="keycloak"

KEYCLOAK_MANIFEST="${ROOT_DIR}/keycloak/keycloak.yaml"
TEAMS_APP_MANIFEST_DIR="${ROOT_DIR}/teams-app/k8s"
OPERATOR_MANIFEST="${ROOT_DIR}/teams-operator/operator-deployment.yaml"

log() {
  printf "%s\n" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

wait_for_deploy() {
  local ns="$1"
  local name="$2"
  kubectl wait --for=condition=available --timeout=300s "deployment/${name}" -n "${ns}"
}

wait_for_rollout() {
  local ns="$1"
  local name="$2"
  kubectl wait --for=condition=Healthy --timeout=300s "rollout/${name}" -n "${ns}"
}

port_forward() {
  require_cmd kubectl

  log "Starting port-forwards (Ctrl+C to stop)..."
  log "- Keycloak: http://localhost:8180"
  log "- Teams UI: http://localhost:4200"
  log "- Teams API: http://localhost:4201"
  log ""

  kubectl port-forward -n "${NAMESPACE_KEYCLOAK}" svc/keycloak-service 8180:8080 >/dev/null 2>&1 &
  local pf_keycloak_pid=$!
  kubectl port-forward -n "${NAMESPACE_PLATFORM}" svc/teams-ui-service 4200:80 >/dev/null 2>&1 &
  local pf_ui_pid=$!
  kubectl port-forward -n "${NAMESPACE_PLATFORM}" svc/teams-api-service 4201:4200 >/dev/null 2>&1 &
  local pf_api_pid=$!

  cleanup_port_forwards() {
    kill "${pf_keycloak_pid}" "${pf_ui_pid}" "${pf_api_pid}" >/dev/null 2>&1 || true
  }

  trap cleanup_port_forwards INT TERM EXIT

  wait
}

deploy() {
  require_cmd kubectl

  log "Deploying Teams demo environment..."

  kubectl apply -f "${KEYCLOAK_MANIFEST}"
  kubectl delete deployment/teams-ui -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl apply -f "${TEAMS_APP_MANIFEST_DIR}"
  kubectl apply -f "${OPERATOR_MANIFEST}"

  log "Waiting for deployments to become ready..."
  wait_for_deploy "${NAMESPACE_KEYCLOAK}" "keycloak"
  wait_for_deploy "${NAMESPACE_PLATFORM}" "teams-api"
  if kubectl get rollout/teams-ui -n "${NAMESPACE_PLATFORM}" >/dev/null 2>&1; then
    wait_for_rollout "${NAMESPACE_PLATFORM}" "teams-ui"
  else
    wait_for_deploy "${NAMESPACE_PLATFORM}" "teams-ui"
  fi
  wait_for_deploy "${NAMESPACE_PLATFORM}" "teams-operator"

  log ""
  log "Deployed. Quick checks:"
  log "kubectl get pods -n ${NAMESPACE_KEYCLOAK}"
  log "kubectl get pods -n ${NAMESPACE_PLATFORM}"
  log ""
  log "Access (port-forward, recommended):"
  log "./workshop/teams-management/demo-deploy.sh port-forward"
  log ""

  log "Optional (if ingress is working):"
  log "- Keycloak: http://platform-auth.127.0.0.1.sslip.io"
  log "- Teams UI: http://teams-ui.127.0.0.1.sslip.io"
  log ""
}

status() {
  require_cmd kubectl

  log "Namespaces:"
  kubectl get ns "${NAMESPACE_KEYCLOAK}" "${NAMESPACE_PLATFORM}" 2>/dev/null || true

  log ""
  log "Keycloak pods/services/ingress:"
  kubectl get pods,svc,ingress -n "${NAMESPACE_KEYCLOAK}" || true

  log ""
  log "Teams platform pods/services/ingress:"
  kubectl get pods,svc,ingress -n "${NAMESPACE_PLATFORM}" || true
}

cleanup() {
  require_cmd kubectl

  log "Removing Teams demo environment resources..."

  kubectl delete -f "${OPERATOR_MANIFEST}" --ignore-not-found
  kubectl delete -f "${TEAMS_APP_MANIFEST_DIR}" --ignore-not-found
  kubectl delete -f "${KEYCLOAK_MANIFEST}" --ignore-not-found

  log "Cleanup complete."
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  port-forward)
    port_forward
    ;;
  status)
    status
    ;;
  cleanup)
    cleanup
    ;;
  *)
    log "Usage: $0 [deploy|port-forward|status|cleanup]"
    exit 1
    ;;
esac
