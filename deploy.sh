#!/usr/bin/env bash
#
# deploy.sh — thin wrapper around the manual steps in MANUAL.md.
# Supports two modes: local (kind) or aws (Terraform/EKS).
#
# Usage:
#   ./scripts/deploy.sh local
#   ./scripts/deploy.sh aws
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required but not installed." >&2; exit 1; }
}

if [[ "$MODE" != "local" && "$MODE" != "aws" ]]; then
  echo "Usage: $0 <local|aws>"
  echo "  local  - create a kind cluster on this machine"
  echo "  aws    - provision a real EKS cluster via Terraform (billable)"
  exit 1
fi

require kubectl
require helm

if [[ "$MODE" == "local" ]]; then
  require kind
  require docker
  echo "==> Creating local kind cluster..."
  kind create cluster --config "$REPO_ROOT/kind-config.yml"
else
  require terraform
  require aws
  echo "==> This will create billable AWS resources (EKS, VPC, NAT gateway)."
  read -r -p "Type 'yes' to continue: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
  echo "==> Running terraform init/apply..."
  (cd "$REPO_ROOT/terraform" && terraform init && terraform apply)
  CLUSTER_NAME="$(grep -A1 'variable "cluster_name"' "$REPO_ROOT/terraform/variables.tf" | grep default | sed -E 's/.*"(.*)".*/\1/')"
  REGION="$(grep -A1 'variable "aws_region"' "$REPO_ROOT/terraform/variables.tf" | grep default | sed -E 's/.*"(.*)".*/\1/')"
  echo "==> Updating kubeconfig for cluster '${CLUSTER_NAME}' in ${REGION}..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
fi

echo "==> Cluster ready. Verifying node access..."
kubectl get nodes

echo "==> Installing Argo CD (if not already present)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for Argo CD server to be ready (this can take a minute)..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

echo "==> Applying the neon-runner Argo CD Application..."
kubectl apply -f "$REPO_ROOT/argocd-neon-runner.yaml"

echo
echo "Deployment triggered. Check status with:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -n neon-runner"
