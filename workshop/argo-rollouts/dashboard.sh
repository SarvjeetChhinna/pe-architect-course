#!/usr/bin/env bash

set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if ! kubectl argo rollouts version >/dev/null 2>&1; then
  echo "kubectl argo-rollouts plugin is required to run the dashboard"
  echo "Install via krew (recommended):"
  echo "  https://krew.sigs.k8s.io/docs/user-guide/setup/install/"
  echo "  kubectl krew install argo-rollouts"
  echo ""
  echo "Or install the plugin binary directly (no krew required):"
  echo "  # Apple Silicon (arm64)"
  echo "  curl -sSL -o kubectl-argo-rollouts https://github.com/argoproj/argo-rollouts/releases/download/v1.8.4/kubectl-argo-rollouts-darwin-arm64"
  echo "  chmod +x kubectl-argo-rollouts"
  echo "  sudo mv kubectl-argo-rollouts /usr/local/bin/"
  echo ""
  echo "  # Intel (amd64)"
  echo "  curl -sSL -o kubectl-argo-rollouts https://github.com/argoproj/argo-rollouts/releases/download/v1.8.4/kubectl-argo-rollouts-darwin-amd64"
  echo "  chmod +x kubectl-argo-rollouts"
  echo "  sudo mv kubectl-argo-rollouts /usr/local/bin/"
  echo "Then run: kubectl argo rollouts dashboard --port 3100"
  exit 1
fi

kubectl argo rollouts dashboard --port 3100
