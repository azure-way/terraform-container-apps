locals {
  prefix     = "${random_pet.rg.id}-${var.environment}"
  prefixSafe = "${random_pet.rg.id}${var.environment}"

  image_name = "containerapps-helloworld:latest"
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

# =============================================================================
# Blue-Green Container App
# =============================================================================
# This Container App uses "Multiple" revision mode so both the "blue" and
# "green" revisions stay active. Traffic is controlled by labels + weights
# via the httpRouteConfigs module.
# =============================================================================

resource "azurerm_container_app" "app" {
  name                         = "${local.prefix}-app"
  container_app_environment_id = azurerm_container_app_environment.app_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Multiple"
  workload_profile_name        = "Consumption"

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ca_identity.id]
  }

  registry {
    identity = azurerm_user_assigned_identity.ca_identity.id
    server   = module.container_registry.url
  }

  template {
    revision_suffix = "blue"

    container {
      name   = "sampleapi"
      image  = "${module.container_registry.url}/${local.image_name}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "REVISION_LABEL"
        value = "blue"
      }
    }

    min_replicas = 1
    max_replicas = 5
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 80

    traffic_weight {
      percentage      = 100
      label           = "blue"
      latest_revision = false
      revision_suffix = "blue"
    }

    traffic_weight {
      percentage      = 0
      label           = "green"
      latest_revision = true
    }
  }

  depends_on = [null_resource.acr_import]
}

# =============================================================================
# Blue-Green Traffic Routing via httpRouteConfigs
# =============================================================================
# This uses the same path_based_routing module from the path-based routing
# article, but instead of routing by path, we route by LABEL and WEIGHT.
#
# To perform a blue-green swap:
#   1. Deploy new code → it becomes the "green" revision
#   2. Change weights: blue=0, green=100
#   3. terraform apply → zero-downtime cutover
#
# To perform a canary rollout:
#   1. Deploy new code → it becomes the "green" revision
#   2. Change weights: blue=90, green=10
#   3. terraform apply → 10% canary
#   4. Gradually increase green weight: 70/30 → 50/50 → 0/100
# =============================================================================

module "blue_green_routing" {
  source = "./modules/path_based_routing"

  routing_name             = "blue-green"
  container_environment_id = azurerm_container_app_environment.app_env.id

  rules = [
    {
      description = "Blue-Green traffic routing"
      routes = [
        {
          match = {
            path          = "/"
            caseSensitive = false
          }
          action = {
            prefixRewrite = "/"
          }
        }
      ]
      targets = [
        {
          containerApp = azurerm_container_app.app.name
          label        = "blue"
          weight       = 100
        },
        {
          containerApp = azurerm_container_app.app.name
          label        = "green"
          weight       = 0
        }
      ]
    }
  ]
}

# =============================================================================
# Outputs
# =============================================================================

output "app_url" {
  value = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "blue_label_url" {
  description = "Direct URL to the blue revision (via label)"
  value       = "https://${azurerm_container_app.app.name}---blue.${azurerm_container_app_environment.app_env.default_domain}"
}

output "green_label_url" {
  description = "Direct URL to the green revision (via label)"
  value       = "https://${azurerm_container_app.app.name}---green.${azurerm_container_app_environment.app_env.default_domain}"
}
