# [Azure Container Apps Jobs – Batch Workloads with Terraform](https://azureway.cloud/azure-container-apps-jobs-batch-workloads-terraform/)

## Overview

This configuration demonstrates all three Azure Container App Job trigger types using Terraform:

- **Manual Jobs** – Triggered on-demand via API, CLI, or the Azure portal. Ideal for ad-hoc batch processing, one-off data migrations, or administrative tasks.
- **Scheduled Jobs** – Run on a cron schedule. Suitable for periodic reports, nightly data processing, or recurring cleanup tasks.
- **Event-Driven Jobs** – Scale based on external events using KEDA scalers. This example uses an Azure Service Bus queue scaler that spins up job replicas when messages are waiting.

## Key Components Created by the Terraform Script

- **Azure Resource Group** – Contains all resources.
- **Azure Virtual Network** – Provides VNet integration for the Container App Environment.
- **Azure Container Registry (Basic SKU)** – Stores the container image used by all three jobs.
- **User Assigned Managed Identity** – Used by Container App Jobs to pull images from ACR.
- **Azure Log Analytics Workspace** – Provides observability for the Container App Environment.
- **Azure Container App Environment** – Hosts all three jobs with Consumption workload profile and VNet integration.
- **Azure Service Bus Namespace & Queue** – Used as the KEDA event source for the event-driven job.
- **Three Container App Jobs**:
  - `manual-job` – Triggered manually.
  - `scheduled-job` – Runs every 6 hours via cron expression `0 */6 * * *`.
  - `event-job` – Scales from 0 to 10 replicas based on Service Bus queue depth.

## Deployment Steps

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/azure-way/terraform-container-apps.git
   cd terraform-container-apps/container_apps_jobs
   ```

2. **Initialize Terraform**:

   ```bash
   terraform init
   ```

3. **Apply Terraform Configuration**:

   ```bash
   terraform apply
   ```

   Provide your Azure service principal credentials when prompted (or configure a `terraform.tfvars` file).

4. **Trigger the Manual Job** (after deployment):

   ```bash
   az containerapp job start --name <manual_job_name> --resource-group <resource_group>
   ```

## Cleanup

To destroy all resources created by Terraform:

```bash
terraform destroy
```

## Additional Resources

- For a detailed walkthrough, refer to the [Azure Way blog post](https://azureway.cloud/azure-container-apps-jobs-batch-workloads-terraform/).
- Explore more articles on Azure Container Apps [here](https://azureway.cloud/category/azure/container-apps/).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

*This README is based on the article "[Azure Container Apps Jobs – Batch Workloads with Terraform](https://azureway.cloud/azure-container-apps-jobs-batch-workloads-terraform/)" by Karol.*
