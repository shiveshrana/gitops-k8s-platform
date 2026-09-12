# DESTROY — Complete Teardown Guide

This reverses everything created in [MANUAL.md](MANUAL.md). Follow the order below — tearing down out of order (e.g., destroying the EKS cluster before removing Argo CD-managed resources) can leave orphaned AWS resources (load balancers, EBS volumes) that Terraform won't know to clean up.

Legend:
- 🟢 **SAFE TO DELETE** — no risk, fully reproducible from Git/Terraform.
- 🟡 **REQUIRES CONFIRMATION** — double-check before running.
- 🔴 **DANGEROUS / IRREVERSIBLE** — destroys billable cloud infrastructure or data; confirm you're targeting the right account/cluster first.

---

## Step 1 — Remove the Argo CD Application (both paths)

🟢 **SAFE TO DELETE**

```bash
kubectl delete -f argocd-neon-runner.yaml
```

This deletes the `Application` resource. Because `prune: true` is set, Argo CD will remove the resources it created (the `neon-runner` Deployments/Services). If it doesn't, force it:

```bash
kubectl delete namespace neon-runner
```

---

## Step 2 — Remove Argo CD Itself (both paths)

🟡 **REQUIRES CONFIRMATION** — only do this if you don't need Argo CD for anything else in the cluster.

```bash
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete namespace argocd
```

---

## Step 3A — Path A Teardown (kind)

🟢 **SAFE TO DELETE** — local only, no cloud cost, fully reproducible with `kind create cluster --config kind-config.yml`.

```bash
kind delete cluster --name kind
```

(Use the actual cluster name from `kind-config.yml`/your `kind get clusters` output if you customized it.)

This removes the Docker containers backing the cluster. Nothing else to clean up for the local path.

---

## Step 3B — Path B Teardown (AWS/Terraform)

🔴 **DANGEROUS / IRREVERSIBLE** — this deletes real AWS infrastructure: the EKS cluster, its node group (EC2 instances), the VPC, subnets, NAT gateway, and associated IAM roles. Confirm you're pointed at the right AWS account/profile first:

```bash
aws sts get-caller-identity
```

Then:

```bash
cd terraform
terraform plan -destroy   # review what will be deleted first
terraform destroy
```

Type `yes` only after reviewing the plan output. This typically takes **5–15 minutes**.

### If `terraform destroy` fails or hangs

This usually happens when Kubernetes-created resources (e.g., a `LoadBalancer`-type Service, which provisions an AWS ELB/NLB outside Terraform's knowledge) still exist inside the cluster. Since this project's Helm chart uses `ClusterIP`/`NodePort` (no `LoadBalancer` type), this shouldn't occur here — but if you changed `values.yaml` to use `LoadBalancer`, delete those Services manually first:

```bash
kubectl get svc -A -o wide | grep LoadBalancer
kubectl delete svc <name> -n <namespace>
```

Then re-run `terraform destroy`.

### Verify nothing billable remains

```bash
aws eks list-clusters --region ap-south-1
aws ec2 describe-vpcs --region ap-south-1 --filters "Name=tag:Project,Values=gitops-k8s-platform"
```

Both should return empty for anything tagged to this project.

---

## Step 4 — Local Cleanup (both paths)

🟢 **SAFE TO DELETE**

```bash
# Remove Terraform's local cache/plugins (safe — re-created by `terraform init`)
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl   # optional: only if you want fresh provider resolution

# Remove any local kubeconfig context you added
kubectl config delete-context kind-kind        # local path
kubectl config delete-context <eks-context>    # AWS path — check `kubectl config get-contexts`

# Remove any local terraform.tfvars you created (never commit this file if it existed)
rm -f terraform/terraform.tfvars
```

🟡 Do **not** delete `terraform/*.tfstate` manually if `terraform destroy` has not been run successfully — Terraform needs the state file to know what to destroy. Only remove state files after a confirmed, successful destroy.

---

## What This Does *Not* Touch

- The Docker Hub images (`shivesh8/neon-runner-backend`, `shivesh8/neon-runner-frontend`) — this project only consumes them, it doesn't manage their lifecycle.
- Your GitHub repository/fork — deleting infrastructure doesn't delete Git history or the repo itself.

---

## Full Teardown Checklist

```text
[ ] Argo CD Application deleted (Step 1)
[ ] neon-runner namespace confirmed gone
[ ] Argo CD removed from cluster, if no longer needed (Step 2)
[ ] kind cluster deleted (Path A) OR terraform destroy completed cleanly (Path B)
[ ] AWS console/CLI confirms no EKS cluster, VPC, or NAT gateway remain tagged to this project
[ ] Local .terraform cache removed
[ ] Local kubeconfig contexts cleaned up
```
