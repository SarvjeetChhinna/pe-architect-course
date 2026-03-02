#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANIFEST_TEMPLATE="${ROOT_DIR}/rollout-required-constraint-template.yaml"
MANIFEST_CONSTRAINT="${ROOT_DIR}/rollout-required-constraint.yaml"
MANIFEST_DENIED_DEPLOYMENT="${ROOT_DIR}/demo-production-deployment-denied.yaml"
MANIFEST_ALLOWED_ROLLOUT="${ROOT_DIR}/demo-production-rollout-allowed.yaml"

log() {
  printf "%s\n" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

enforce() {
  require_cmd kubectl

  log "== Gatekeeper demo: enforce Rollouts in production =="

  log "[1/4] Apply ConstraintTemplate + Constraint"
  kubectl apply -f "${MANIFEST_TEMPLATE}"
  kubectl apply -f "${MANIFEST_CONSTRAINT}"

  log "[2/4] Show DENY (Deployment in production)"
  set +e
  kubectl apply -f "${MANIFEST_DENIED_DEPLOYMENT}"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    log "WARNING: Deployment applied successfully (policy may not be enforcing yet)."
    log "If this happens, wait a few seconds and re-run: $0 deny"
  fi

  log "[3/4] Show ALLOW (Rollout in production)"
  kubectl apply -f "${MANIFEST_ALLOWED_ROLLOUT}"
  kubectl get rollout -n production || true

  log "[4/4] Done"
}

deny() {
  require_cmd kubectl
  log "Applying denied Deployment manifest (expected to FAIL)..."
  kubectl apply -f "${MANIFEST_DENIED_DEPLOYMENT}"
}

allow() {
  require_cmd kubectl
  log "Applying allowed Rollout manifest (expected to PASS)..."
  kubectl apply -f "${MANIFEST_ALLOWED_ROLLOUT}"
  kubectl get rollout -n production || true
}

cleanup() {
  require_cmd kubectl

  log "== Gatekeeper demo cleanup (repeatable) =="

  kubectl delete -f "${MANIFEST_ALLOWED_ROLLOUT}" --ignore-not-found
  kubectl delete -f "${MANIFEST_DENIED_DEPLOYMENT}" --ignore-not-found
  kubectl delete ns production --ignore-not-found

  log "Optional: remove policy too (uncomment if desired):"
  log "kubectl delete -f ${MANIFEST_CONSTRAINT} --ignore-not-found"
  log "kubectl delete -f ${MANIFEST_TEMPLATE} --ignore-not-found"

  log "Cleanup complete."
}

case "${1:-enforce}" in
  enforce)
    enforce
    ;;
  deny)
    deny
    ;;
  allow)
    allow
    ;;
  cleanup)
    cleanup
    ;;
  *)
    log "Usage: $0 [enforce|deny|allow|cleanup]"
    exit 1
    ;;
esac
