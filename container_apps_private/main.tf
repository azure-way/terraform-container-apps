locals {
  prefix   = var.environment
  location = var.location
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = local.prefix
  location = local.location
}

resource "azurerm_log_analytics_workspace" "aca_logs" {
  name                = "${local.prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

module "virtual_network" {
  source = "./modules/virtual_network"

  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  name                      = "${local.prefix}-vnet"
  address_space             = ["40.0.0.0/16"]
  subnet_address_prefix_map = var.subnet_address_prefix_map

  prefix = local.prefix
}

resource "azurerm_container_app_environment" "aca_env" {
  name                       = "${local.prefix}-aca-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aca_logs.id

  infrastructure_subnet_id           = module.virtual_network.app_subnet_id
  infrastructure_resource_group_name = "${local.prefix}-aca-infra"
  internal_load_balancer_enabled     = true

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    maximum_count         = 0
    minimum_count         = 0
  }
}

resource "azurerm_container_app" "sampleapi" {
  name                         = "${local.prefix}-app"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  template {
    container {
      name   = "sampleapi"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }

    min_replicas = 0
    max_replicas = 5
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 80

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

resource "azurerm_private_dns_zone" "example" {
  name                = azurerm_container_app_environment.aca_env.default_domain
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "${azurerm_container_app_environment.aca_env.name}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = module.virtual_network.id
}

resource "azurerm_private_dns_a_record" "example" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.example.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.aca_env.static_ip_address]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "jump-host-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_network_interface" "jump_nic" {
  name                = "${local.prefix}-jump-host-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.virtual_network.vm_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_windows_virtual_machine" "jump_vm" {
  name                = "${local.prefix}-jumpvm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D4_v5"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  patch_mode          = "AutomaticByPlatform"
  network_interface_ids = [
    azurerm_network_interface.jump_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}