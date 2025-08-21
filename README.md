# AKS Infra Automation

This repo bootstraps Azure remote state then provisions a **private AKS cluster** with a jumpbox VM, VNet/NSGs, NAT Gateway, ACR, and Log Analytics. It does **not** deploy your apps. You can chain your separate front-end/back-end pipelines and Argo CD after infra is up.

## Prereqs
- Azure subscription + permissions to create resources
- GitHub OIDC to Azure with secrets:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- Define repo-level variables: `AZURE_LOCATION` (e.g., `eastus`), `PROJECT_NAME` (e.g., `revinci`).

## 1) Bootstrap remote state
Run GitHub Action **Terraform Backend Setup** (or locally run `backend-setup/`). Note the outputs and set them when initializing backend for the main stack.

## 2) Deploy AKS infra
Update `environments/*.tfvars` with your CIDRs and IP allow list, then run the **Deploy AKS Infra** workflow. It applies the environment chosen by the `ENVIRONMENT` variable (default `dev`).

## Connectivity
- AKS is **private**; use the **jumpbox** SSH: `ssh azureuser@<jumpbox_public_ip>` then `az aks get-credentials` via Azure CLI on the VM.
- API server resolves via private DNS zone: `privatelink.<region>.azmk8s.io`.

## Notes
- Kubernetes version pinned to `1.32.0` as requested; update as needed.
- OMS agent add-on is enabled and sends logs to Log Analytics (7 days retention).
- Two node pools: `system` (critical add-ons) and `usernp` (tainted for workloads).
- ACR is RBAC-integrated; `AcrPull` assigned to AKS kubelet identity.

## Destroy
Use Terraform `destroy` from `terraform-aks/` with the same backend and tfvars. Destroy backend resources last.
