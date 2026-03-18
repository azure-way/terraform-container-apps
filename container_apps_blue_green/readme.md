# Azure Container Apps – Blue-Green Deployments with Terraform

## Overview

This example demonstrates how to implement **blue-green deployments** on Azure Container Apps using **revision labels**, **traffic weight splitting**, and **httpRouteConfigs** — all managed through Terraform.

### What is Blue-Green Deployment?

Blue-green deployment is a release strategy that reduces downtime and risk by running two identical production environments:
- **Blue** — the current production version receiving 100% traffic
- **Green** — the new version receiving 0% traffic (ready for testing)

When the green version is validated, traffic is switched from blue to green instantly. If something goes wrong, you can roll back by switching traffic back to blue.

### Why Labels Instead of Revision Names?

Azure Container Apps auto-generates revision names (e.g., `myapp--abc1234`), making them unpredictable in Infrastructure as Code. **Labels** provide stable, human-readable identifiers:
- `blue` always points to the current production revision
- `green` always points to the new candidate revision

You can also access each label directly via its URL:
- `https://myapp---blue.<environment-domain>`
- `https://myapp---green.<environment-domain>`

## Key Components

- **Azure Container App** with `revision_mode = "Multiple"` and labeled traffic weights
- **httpRouteConfigs** (via `azapi`) for label-based traffic routing
- **Azure Container Registry** with managed identity access
- **Virtual Network** with Container Apps subnet delegation
- **Log Analytics Workspace** for monitoring

## Deployment Patterns

### Blue-Green Swap (Zero Downtime)

1. Deploy with blue receiving 100% traffic
2. Deploy new image → creates green revision
3. Update weights: `blue=0, green=100`
4. `terraform apply` → instant cutover

### Canary Rollout (Gradual)

1. Deploy with blue receiving 100% traffic
2. Deploy new image → creates green revision
3. Update weights: `blue=90, green=10` → 10% canary
4. Monitor, then increase: `70/30` → `50/50` → `0/100`

## How to Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Source Code

Full article: [Azure Container Apps – Blue-Green Deployments with Terraform](https://azureway.cloud/)

GitHub Repository: [azure-way/terraform-container-apps](https://github.com/azure-way/terraform-container-apps)
