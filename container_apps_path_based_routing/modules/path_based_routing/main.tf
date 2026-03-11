# Configure the Azure provider
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
   }
  }
}

variable "container_environment_id" {
  description = "The ID of the container environment"
}

variable "routing_name" {
  description = "The name of the HTTP route configuration"
}

variable "rules" {
  description = "The rules for the HTTP route configuration"
  type = list(object(
    {
      description = optional(string)
      routes = optional(list(object({
        action = optional(object({
          prefixRewrite = optional(string)
        }))
        match = optional(object({
          caseSensitive       = optional(bool)
          path                = optional(string)
          pathSeparatedPrefix = optional(string)
          prefix              = optional(string)
        }))
      })))
      targets = optional(list(object({
        containerApp = optional(string)
        label        = optional(string)
        revision     = optional(string)
        weight       = optional(number)
      })))
    }
  ))


}

resource "azapi_resource" "symbolicname" {
  type      = "Microsoft.App/managedEnvironments/httpRouteConfigs@2025-10-02-preview"
  name      = var.routing_name
  parent_id = var.container_environment_id
  body = {
    properties = {
      rules = var.rules
    }
  }
}