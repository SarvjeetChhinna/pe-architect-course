#!/usr/bin/env bash

set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

kubectl delete namespace rollouts-demo --ignore-not-found
