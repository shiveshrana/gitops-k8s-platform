#!/usr/bin/env bash
#
# destroy.sh — thin wrapper around the manual steps in DESTROY.md.
# Reverses what deploy.sh created.
#
# Usage:
#   ./scripts/destroy.sh local
#   ./scripts/destroy.sh aws
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"

if [[ "$MODE" != "local" && "$MODE" != "aws" ]]; then
  echo "Usage: $0 <local|aws>"
  exit 1
fi

echo "==> Removing the neon-runner Argo CD Application (this prunes its managed resources)..."
kubectl delete -f "$REPO_ROOT/argocd-neon-runner.yaml" --ignore-not-found=true

echo "==> Confirming neon-runner namespace is gone (forcing if needed)..."
kubectl delete namespace neon-runner --ignore-not-found=true

read -r -p "Also remove Argo CD itself from this cluster? [y/N] " REMOVE_ARGOCD
if [[ "$REMOVE_ARGOCD" == "y" || "$REMOVE_ARGOCD" == "Y" ]]; then
  kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true
  kubectl delete namespace argocd --ignore-not-found=true
fi

if [[ "$MODE" == "local" ]]; then
  echo "==> Deleting local kind cluster..."
  kind delete cluster --name kind
else
  echo "!!! This will destroy real AWS infrastructure (EKS cluster, VPC, NAT gateway, node group)."
  echo "!!! Review the plan carefully before confirming."
  (cd "$REPO_ROOT/terraform" && terraform plan -destroy)
  read -r -p "Type 'destroy' to proceed: " CONFIRM
  if [[ "$CONFIRM" != "destroy" ]]; then
    echo "Aborted. No AWS resources were touched."
    exit 1
  fi
  (cd "$REPO_ROOT/terraform" && terraform destroy)
fi

echo "==> Cleaning local Terraform cache..."
rm -rf "$REPO_ROOT/terraform/.terraform"

echo "Done. See DESTROY.md to manually verify no billable AWS resources remain."
