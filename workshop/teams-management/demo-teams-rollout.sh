#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE_PLATFORM="engineering-platform"

IMAGE_TAG_TARGET="v0.1.4"

MANIFESTS_TEAMS_APP_K8S_DIR="${ROOT_DIR}/teams-app/k8s"
MANIFEST_TEAMS_UI_ROLLOUT="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-ui-rollout.yaml"
MANIFEST_TEAMS_UI_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-ui-service.yaml"
MANIFEST_TEAMS_UI_CANARY_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-ui-canary-service.yaml"

MANIFEST_TEAMS_API_ROLLOUT="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-api-deployment.yaml"
MANIFEST_TEAMS_API_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-api-service.yaml"
MANIFEST_TEAMS_API_CANARY_SERVICE="${MANIFESTS_TEAMS_APP_K8S_DIR}/teams-api-canary-service.yaml"

MANIFEST_TEAMS_OPERATOR_ROLLOUT="${ROOT_DIR}/teams-operator/operator-rollout.yaml"

log() {
  printf "%s\n" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

require_rollouts_plugin() {
  if ! kubectl argo rollouts version >/dev/null 2>&1; then
    log "kubectl argo-rollouts plugin is required (kubectl argo rollouts ...)"
    exit 1
  fi
}

wait_for_rollout_healthy() {
  local name="$1"
  kubectl wait --for=condition=Healthy --timeout=300s "rollout/${name}" -n "${NAMESPACE_PLATFORM}"
}

main() {
  require_cmd kubectl
  require_rollouts_plugin

  log "== Teams complete app rollout demo: upgrading to ${IMAGE_TAG_TARGET} =="
  log "Namespace: ${NAMESPACE_PLATFORM}"
  log ""

  log "[1/6] Ensure stable/canary services exist (UI + API)"
  kubectl apply -f "${MANIFEST_TEAMS_UI_SERVICE}"
  kubectl apply -f "${MANIFEST_TEAMS_UI_CANARY_SERVICE}"
  kubectl apply -f "${MANIFEST_TEAMS_API_SERVICE}"
  kubectl apply -f "${MANIFEST_TEAMS_API_CANARY_SERVICE}"

  log "[2/6] Convert teams-ui Deployment -> Rollout"
  kubectl delete deployment teams-ui -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl apply -f "${MANIFEST_TEAMS_UI_ROLLOUT}"

  log "[3/6] Convert teams-api Deployment -> Rollout"
  kubectl delete deployment teams-api -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl apply -f "${MANIFEST_TEAMS_API_ROLLOUT}"

  log "[4/6] Convert teams-operator Deployment -> Rollout"
  kubectl delete deployment teams-operator -n "${NAMESPACE_PLATFORM}" --ignore-not-found
  kubectl apply -f "${MANIFEST_TEAMS_OPERATOR_ROLLOUT}"

  log "[5/6] Set images to ${IMAGE_TAG_TARGET}"
  kubectl argo rollouts set image teams-ui -n "${NAMESPACE_PLATFORM}" \
    teams-ui="ghcr.io/sarvjeetchhinna/pe-platform-capstone/teams-app:${IMAGE_TAG_TARGET}"

  kubectl argo rollouts set image teams-api -n "${NAMESPACE_PLATFORM}" \
    teams-api="ghcr.io/sarvjeetchhinna/pe-platform-capstone/teams-api:${IMAGE_TAG_TARGET}"

  kubectl argo rollouts set image teams-operator -n "${NAMESPACE_PLATFORM}" \
    teams-operator="ghcr.io/sarvjeetchhinna/pe-platform-capstone/teams-operator:${IMAGE_TAG_TARGET}"

  log "[6/6] Wait for rollouts to become Healthy"
  wait_for_rollout_healthy "teams-ui"
  wait_for_rollout_healthy "teams-api"
  wait_for_rollout_healthy "teams-operator"

  log ""
  log "Done. Quick checks:"
  log "- kubectl get rollout -n ${NAMESPACE_PLATFORM}"
  log "- kubectl argo rollouts list rollouts -n ${NAMESPACE_PLATFORM}"
  log ""
  log "Suggested access (port-forward):"
  log "- ${ROOT_DIR}/demo-deploy.sh port-forward"
}

main "$@"
