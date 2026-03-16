locals {
  prefix     = "${random_pet.rg.id}-${var.environment}"
  prefixSafe = "${random_pet.rg.id}${var.environment}"

  image_name               = "containerapps-helloworld:latest"
  servicebus_consumer_image = "sample-service-bus-consumer:latest"
}

data "azurerm_client_config" "current" {}

resource "random_id" "random" {
  byte_length = 4
}

resource "random_pet" "rg" {
  length = 1
}

resource "azurerm_resource_group" "rg" {
  name     = local.prefix
  location = var.location
}

resource "azurerm_user_assigned_identity" "ca_identity" {
  location            = var.location
  name                = "ca_identity"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "acrpull_mi" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ca_identity.principal_id
}

resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = "${local.prefix}-la"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.la_sku
  retention_in_days   = var.la_retenction_days
}

module "virtual_network" {
  source = "./modules/virtual_network"

  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location

  name                      = "${local.prefix}-vnet"
  address_space             = var.address_space
  subnet_address_prefix_map = var.subnet_address_prefix_map

  prefix = local.prefix
}

module "container_registry" {
  source = "./modules/container_registry"

  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location

  name = "${local.prefixSafe}acr"
}

resource "azurerm_container_app_environment" "app_env" {
  name                       = "${local.prefix}-environment"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id

  infrastructure_subnet_id           = module.virtual_network.app_subnet_id
  infrastructure_resource_group_name = "${azurerm_resource_group.rg.name}-infra"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    maximum_count         = 0
    minimum_count         = 0
  }
}

resource "time_sleep" "wait_60_seconds" {
  depends_on = [module.container_registry]

  create_duration = "60s"
}

resource "null_resource" "acr_import" {
  provisioner "local-exec" {
    command = <<-EOT
        az acr import \
            --name ${module.container_registry.name} \
            --source mcr.microsoft.com/azuredocs/${local.image_name} \
            --image ${local.image_name}
      EOT
  }

  depends_on = [time_sleep.wait_60_seconds]
}

resource "null_resource" "acr_build_servicebus_consumer" {
  provisioner "local-exec" {
    command = <<-EOT
        az acr build \
            --registry ${module.container_registry.name} \
            --image ${local.servicebus_consumer_image} \
            ../container_apps_servicebus/1_samples/ContainerAppsServiceBusSample
      EOT
  }

  depends_on = [time_sleep.wait_60_seconds]
}

resource "azurerm_servicebus_namespace" "sb" {
  name                = "${local.prefix}-servicebus"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "job_queue" {
  name         = "job-tasks"
  namespace_id = azurerm_servicebus_namespace.sb.id

  enable_partitioning = false
}

resource "azurerm_container_app_job" "manual_job" {
  name                         = "${local.prefix}-manual-job"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.app_env.id
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 1

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "manual-job"
      image  = "${module.container_registry.url}/${local.image_name}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "JOB_TYPE"
        value = "manual"
      }
    }
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ca_identity.id]
  }

  registry {
    identity = azurerm_user_assigned_identity.ca_identity.id
    server   = module.container_registry.url
  }

  depends_on = [null_resource.acr_import]
}

resource "azurerm_container_app_job" "scheduled_job" {
  name                         = "${local.prefix}-scheduled-job"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.app_env.id
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 1

  schedule_trigger_config {
    cron_expression          = "0 */6 * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "scheduled-job"
      image  = "${module.container_registry.url}/${local.image_name}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "JOB_TYPE"
        value = "scheduled"
      }
    }
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ca_identity.id]
  }

  registry {
    identity = azurerm_user_assigned_identity.ca_identity.id
    server   = module.container_registry.url
  }

  depends_on = [null_resource.acr_import]
}

resource "azurerm_container_app_job" "event_driven_job" {
  name                         = "${local.prefix}-event-job"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.app_env.id
  replica_timeout_in_seconds   = 600
  replica_retry_limit          = 2

  event_trigger_config {
    parallelism              = 1
    replica_completion_count = 1

    scale {
      min_executions              = 0
      max_executions              = 10
      polling_interval_in_seconds = 30

      rules {
        name = "servicebus-queue-rule"
        type = "azure-servicebus"
        metadata = {
          queueName    = azurerm_servicebus_queue.job_queue.name
          namespace    = azurerm_servicebus_namespace.sb.name
          messageCount = "5"
        }
        authentication {
          secret_name       = "service-bus-connection-string"
          trigger_parameter = "connection"
        }
      }
    }
  }

  secret {
    name  = "service-bus-connection-string"
    value = azurerm_servicebus_namespace.sb.default_primary_connection_string
  }

  template {
    container {
      name   = "event-job"
      image  = "${module.container_registry.url}/${local.servicebus_consumer_image}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "serviceBusConnectionString"
        secret_name = "service-bus-connection-string"
      }

      env {
        name  = "serviceBusQueue"
        value = azurerm_servicebus_queue.job_queue.name
      }
    }
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ca_identity.id]
  }

  registry {
    identity = azurerm_user_assigned_identity.ca_identity.id
    server   = module.container_registry.url
  }

  depends_on = [null_resource.acr_build_servicebus_consumer]
}

output "manual_job_name" {
  value = azurerm_container_app_job.manual_job.name
}

output "scheduled_job_name" {
  value = azurerm_container_app_job.scheduled_job.name
}

output "event_driven_job_name" {
  value = azurerm_container_app_job.event_driven_job.name
}

output "servicebus_namespace" {
  value     = azurerm_servicebus_namespace.sb.name
  sensitive = true
}
