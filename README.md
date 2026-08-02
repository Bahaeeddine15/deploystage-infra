# deploystage-infra

Terraform-provisioned Azure infrastructure for [DeployStage](https://github.com/bahaeeddine15/deploystage): AKS, ACR, a managed Postgres instance, networking, and the Jenkins VM.

## What it provisions

- Resource group, VNet/subnet/NSG
- AKS cluster (single `Standard_B2s_v2` node) with the `AcrPull` role assigned to its kubelet identity
- ACR (container registry)
- Jenkins VM (Linux, Docker + Azure CLI + kubectl installed manually — see setup notes below)
- Azure Database for PostgreSQL (Flexible Server, Burstable tier)
- Prometheus + Grafana via the `kube-prometheus-stack` Helm chart (not Terraform-managed — installed separately, see below)

## Setup

```
terraform init
terraform plan
terraform apply
```

You'll need a `terraform.tfvars` (gitignored) with:
```
db_admin_password = "your-password-here"
```

## Region constraint

**Azure for Students subscriptions are restricted to a specific region allowlist**, which does not match Azure's general documentation. Find your subscription's actual allowed regions with:
```
az policy assignment list --query "[?displayName=='Allowed resource deployment regions'].parameters" -o json
```
This project uses `Sweden Central`.

## Jenkins setup (manual, post-Terraform)

Terraform provisions the VM; Jenkins itself is installed manually via SSH:
1. Install Java 21 (current Jenkins LTS requirement), Jenkins itself, Docker, Azure CLI, kubectl
2. Add both users (`jenkins`, your SSH user) to the `docker` group
3. Create an Azure Service Principal scoped to this resource group (`az ad sp create-for-rbac --role Contributor --scopes /subscriptions/.../resourceGroups/deploystage-rg`) and store its credentials as Jenkins Secret text credentials
4. Install the **Docker Pipeline** and **Kubernetes CLI** plugins (there is no "Azure CLI" Jenkins plugin — Azure CLI is installed directly on the VM and invoked via shell steps)

## Observability

Prometheus/Grafana are installed via Helm, not Terraform:
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword='...' \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=1Gi
```
Note the `kube-prometheus-stack` chart uses **ServiceMonitor CRDs** for scrape discovery, not the older `prometheus.io/scrape` annotation convention — any ServiceMonitor you add needs a `release: monitoring` label to match the Helm release, or the Prometheus Operator silently ignores it.

## Cost management

Both AKS and the Jenkins VM should be stopped when not in active use:
```
az aks stop --name deploystage-aks --resource-group deploystage-rg
az vm deallocate --name jenkins-vm --resource-group deploystage-rg
```
(`deallocate`, not `stop`, for the VM — `stop` alone can still incur compute charges.)

## Notable gotchas hit building this

- VM SKU availability (`Standard_B1s`) can vary by region due to capacity restrictions unrelated to subscription policy — check `az vm list-skus` if a deployment fails with `SkuNotAvailable`.
- The `azurerm` Terraform provider has a known polling bug (`unimplemented polling status "Unknown"`) on AKS creation; if this happens, check `az aks show --query provisioningState` directly and `terraform import` the resource once it's confirmed `Succeeded`.