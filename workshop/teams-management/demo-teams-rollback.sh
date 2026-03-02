#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE_PLATFORM="engineering-platform"

IMAGE_TAG_BASELINE="v0.1.2"

MANIFESTS_TEAMS_APP_K8S_DIR="${ROOT_DIR}/teams-app/k8s"
MANIFEST_TEAMS_UI_DEPLOYMENT="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-ui-deployment.yaml"
MANIFEST_TEAMS_UI_CANARY_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-ui-canary-service.yaml"

MANIFEST_TEAMS_API_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-api-service.yaml"
MANIFEST_TEAMS_API_CANARY_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-api-canary-service.yaml"

MANIFEST_TEAMS_API_BASELINE_DEPLOYMENT="${ROOT_DIR}/teams-api/deployment.yaml"
MANIFEST_TEAMS_OPERATOR_BASELINE_DEPLOYMENT="${ROOT_DIR}/teams-operator/operator-deployment.yaml"

log() {
  printf "%s\n" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

wait_for_deploy_available() {
  local name="$1"
  kubectl wait --for=condition=available --timeout=300s "deployment/${name}" -n "${NAMESPACE_PLATFORM}"
}

cleanup_team_namespaces() {
  local prefix="${1:-}"
  if [[ -z "${prefix}" ]]; then
    log "Skipping team namespace cleanup (no prefix provided)."
    log "If you want, run: $0 cleanup-namespaces <prefix>"
    return 0
  fi

  log "Deleting namespaces with prefix '${prefix}' (best-effort)"
  # shellcheck disable=SC2207
  local namespaces=( $(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep "^${prefix}" || true) )
  if [[ ${#namespaces[@]} -eq 0 ]]; then
    log "No namespaces found with prefix '${prefix}'."
    return 0
  fi

  for ns in "${namespaces[@]}"; do
    kubectl delete ns "${ns}" --ignore-not-found
  done
}

rollback() {
  require_cmd kubectl

  log "== Teams demo rollback: restoring baseline ${IMAGE_TAG_BASELINE} =="
  log "Namespace: ${NAMESPACE_PLATFORM}"
  log ""

  log "[1/6] Delete Rollouts (teams-ui, teams-api, teams-operator)"
  kubectl delete rollout teams-ui -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl delete rollout teams-api -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl delete rollout teams-operator -n "${NAMESPACE_PLATFORM}" --ignore-not-found

  log "[2/6] Delete canary services (UI + API)"
  kubectl delete svc teams-ui-canary-service -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl delete svc teams-api-canary-service -n "${NAMESPACE_PLATFORM}" --ignore-not-found

  log "[3/6] Restore teams-ui Deployment"
  kubectl apply -f "${MANIFEST_TEAMS_UI_DEPLOYMENT}"
  kubectl set image deployment/teams-ui -n "${NAMESPACE_PLATFORM}" \
    teams-ui="ghcr.io/sarvjeetchhinna/pe-platform-capstone/teams-app:${IMAGE_TAG_BASELINE}"
  wait_for_deploy_available "teams-ui"

  log "[4/6] Restore teams-api Deployment"
  kubectl apply -f "${MANIFEST_TEAMS_API_SERVICE}"
  kubectl apply -f "${MANIFEST_TEAMS_API_BASELINE_DEPLOYMENT}"
  kubectl set image deployment/teams-api -n "${NAMESPACE_PLATFORM}" \
    teams-api="ghcr.io/sarvjeetchhinna/pe-platform-capstone/teams-api:${IMAGE_TAG_BASELINE}"
  wait_for_deploy_available "teams-api"

  log "[5/6] Restore teams-operator Deployment"
  kubectl apply -f "${MANIFEST_TEAMS_OPERATOR_BASELINE_DEPLOYMENT}"
  kubectl set image deployment/teams-operator -n "${NAMESPACE_PLATFORM}" \
    teams-operator="ghcr.io/sarvjeetchhinna/pe-platform-capstone/teams-operator:${IMAGE_TAG_BASELINE}"
  wait_for_deploy_available "teams-operator"

  log "[6/6] Status"
  kubectl get deploy -n "${NAMESPACE_PLATFORM}" teams-ui teams-api teams-operator \
    -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'

  log ""
  log "Rollback complete."
}

case "${1:-rollback}" in
  rollback)
    rollback
    ;;
  cleanup-namespaces)
    cleanup_team_namespaces "${2:-}"
    ;;
  *)
    log "Usage: $0 [rollback|cleanup-namespaces <prefix>]"
    exit 1
    ;;
esac
