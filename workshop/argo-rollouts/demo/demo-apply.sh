#!/usr/bin/env bash

set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl apply -f "${SCRIPT_DIR}/demo-rollout.yaml"

kubectl get rollout -n rollouts-demo
kubectl get pods -n rollouts-demo
