# MANUAL — Operating This Project From Zero

This manual assumes you have just cloned the repository and have nothing else set up. It covers both supported paths:

- **Path A — Local only**, using `kind`. No AWS account needed, no cost.
- **Path B — AWS/EKS**, using Terraform. Real cloud infrastructure, incurs cost.

Both paths converge at the same step: installing Argo CD and applying `argocd-neon-runner.yaml`.

---

## 1. Prerequisites

### Required software (both paths)

| Tool | Minimum version | Check with |
|---|---|---|
| Git | any recent | `git --version` |
| kubectl | compatible with K8s 1.3x | `kubectl version --client` |
| Helm | v3.x | `helm version` |

### Path A only (local)

| Tool | Check with |
|---|---|
| Docker | `docker --version` |
| kind | `kind --version` |

### Path B only (AWS)

| Tool | Check with |
|---|---|
| Terraform | `terraform --version` (must be `>= 1.5.0`) |
| AWS CLI | `aws --version` |
| An AWS account with permissions to create VPCs, EKS clusters, IAM roles, and EC2 instances | — |

### Required accounts

- GitHub account (to fork/host your copy of this repo, since Argo CD pulls from a Git URL).
- Docker Hub account is **not** required to run this project as-is — it already references public pre-built images (`shivesh8/neon-runner-backend`, `shivesh8/neon-runner-frontend`). You'd only need one if you build your own images.
- AWS account — Path B only.

---

## 2. Repository Setup

```bash
git clone https://github.com/shiveshrana/gitops-k8s-platform.git
cd gitops-k8s-platform
```

If you intend to run this from your **own fork** (recommended so Argo CD points at a repo you control), also update the source URL:

```bash
# In argocd-neon-runner.yaml
# Change:
#   repoURL: https://github.com/shiveshrana/gitops-k8s-platform.git
# To:
#   repoURL: https://github.com/<your-username>/gitops-k8s-platform.git
```

---

## 3. Configuration

No `.env` file or secret material is required for this project. The two files you may want to adjust:

- `terraform/variables.tf` (Path B) — `aws_region` (default `ap-south-1`), `cluster_name` (default `gitops-platform`). Override via a local `terraform.tfvars` (already git-ignored) instead of editing the defaults directly:

  ```hcl
  # terraform/terraform.tfvars  (do not commit if it contains anything sensitive)
  aws_region   = "ap-south-1"
  cluster_name = "my-gitops-platform"
  ```

- `k8s/neon-runner/values.yaml` — image tags, replica counts, service types.

### Authentication

- **Path B (AWS):** configure credentials before running Terraform:

  ```bash
  aws configure
  # or
  export AWS_PROFILE=your-profile-name
  ```

---

## 4A. Path A — Local Setup (kind)

```bash
kind create cluster --config kind-config.yml
```

This creates a 3-node cluster (1 control-plane, 2 workers) named per `kind-config.yml`.

Verify:

```bash
kubectl cluster-info --context kind-kind
kubectl get nodes
```

Skip to [Section 5 — Install Argo CD](#5-install-argo-cd-both-paths).

---

## 4B. Path B — AWS Setup (Terraform/EKS)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted. This provisions:
- A VPC with public/private subnets across 3 AZs in `ap-south-1`.
- An EKS cluster with one managed node group (`t3.small`, 1–2 nodes).

This step typically takes **10–20 minutes**.

⚠️ **This creates real, billable AWS resources** (EKS control plane, EC2 nodes, NAT gateway, EIP). Do not leave it running if you're not actively using it — see [DESTROY.md](DESTROY.md).

Once complete, point `kubectl` at the new cluster:

```bash
aws eks update-kubeconfig --region ap-south-1 --name gitops-platform
kubectl get nodes
```

(Use whatever `aws_region`/`cluster_name` you actually set in step 3 if you overrode the defaults.)

Return to the repo root:

```bash
cd ..
```

---

## 5. Install Argo CD (both paths)

This repository does not include Argo CD's own installation manifests — install it using Argo CD's official manifests:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for pods to be ready:

```bash
kubectl get pods -n argocd -w
```

(Press Ctrl+C once everything shows `Running`/`Completed`.)

### Access the Argo CD UI (optional)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open `https://localhost:8080`. Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## 6. Deploy the Application

```bash
kubectl apply -f argocd-neon-runner.yaml
```

This creates the `neon-runner` Argo CD `Application`, which will:
1. Create the `neon-runner` namespace (via `CreateNamespace=true`).
2. Sync the `k8s/neon-runner` Helm chart into it.
3. Continuously watch this repo and auto-heal any drift.

---

## 7. Verification

```bash
# Argo CD sync/health status
kubectl get applications -n argocd
kubectl describe application neon-runner -n argocd

# Application pods/services
kubectl get pods -n neon-runner
kubectl get svc -n neon-runner
```

Expect `neon-runner-backend` (2 replicas) and `neon-runner-frontend` (3 replicas) `Running` and `Ready`.

### Reaching the app locally (kind path)

```bash
kubectl port-forward svc/neon-runner-frontend -n neon-runner 8080:8080
# then open http://localhost:8080
```

---

## 8. Testing

No automated test suite exists in this repository. Manual verification is limited to the health-check steps above (readiness/liveness probes are configured on both Deployments and can be inspected with `kubectl describe pod`).

---

## 9. Logs & Monitoring

No monitoring stack (Prometheus/Grafana) or alerting is set up by this repository. For ad-hoc debugging:

```bash
kubectl logs -n neon-runner deploy/neon-runner-backend
kubectl logs -n neon-runner deploy/neon-runner-frontend
kubectl logs -n argocd deploy/argocd-application-controller
```

---

## 10. Troubleshooting

| Problem | Check | Fix |
|---|---|---|
| `terraform apply` errors with credential/auth failure | `aws sts get-caller-identity` | Reconfigure AWS credentials |
| Argo CD `Application` stuck `Unknown`/`OutOfSync` | `repoURL` value | Point it at a repo Argo CD can actually reach (public HTTPS URL or configure repo credentials in Argo CD) |
| `ImagePullBackOff` on pods | `kubectl describe pod <name> -n neon-runner` | Confirm the image tag in `values.yaml` exists on Docker Hub |
| `kind create cluster` hangs or fails | `docker ps` | Ensure Docker daemon is running and has enough resources allocated |
| Argo CD reverts your manual `kubectl edit` | This is expected | `selfHeal: true` is set intentionally — change the Git source instead |

---

## 11. Stopping the Project (without destroying)

**Path A (kind):** stop Docker Desktop/daemon, or simply leave the cluster running — it only consumes local resources.

**Path B (AWS):** there is no "pause" for EKS — the control plane and node group bill continuously. To temporarily stop cost without a full destroy, you can scale the node group to zero:

```bash
# Adjust via terraform/main.tf desired_size, or directly:
aws eks update-nodegroup-config \
  --cluster-name gitops-platform \
  --nodegroup-name default \
  --scaling-config minSize=0,maxSize=2,desiredSize=0
```

(The EKS control plane itself still bills hourly regardless — full teardown is the only way to stop that cost. See [DESTROY.md](DESTROY.md).)

---

## 12. Restarting the Project

**Path A:** `kind create cluster --config kind-config.yml` again if you deleted it, then repeat from Section 5.

**Path B:** scale the node group back up (reverse of Section 11), or re-run `terraform apply` if you fully destroyed it.

---

## 13. Completely Removing the Project

See [DESTROY.md](DESTROY.md) for the full, ordered teardown of everything created above.
