#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="argo-rollouts"
INSTALL_URL="https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${NAMESPACE}" -f "${INSTALL_URL}"

kubectl rollout status deployment/argo-rollouts -n "${NAMESPACE}" --timeout=300s

kubectl get pods -n "${NAMESPACE}"
