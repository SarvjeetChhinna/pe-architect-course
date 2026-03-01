#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="argo-rollouts"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

kubectl delete namespace "${NAMESPACE}" --ignore-not-found
kubectl delete crd rollouts.argoproj.io experiments.argoproj.io analysistemplates.argoproj.io clusteranalysistemplates.argoproj.io --ignore-not-found
