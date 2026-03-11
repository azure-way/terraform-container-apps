variable "environment" {
  description = "Name of the environment"
  default     = "exec"
}

variable "applicationName" {
  description = "Name of the application"
  default     = "container-app"
}

variable "location" {
  description = "Primary location of the services"
  default     = "westeurope"
}

variable "address_space" {
  type    = list(string)
  default = ["40.0.0.0/16"]
}
variable "subnet_address_prefix_map" {
  type = map(list(string))
  default = {
    "app" = ["40.0.0.0/23"]
  }
}

variable "la_sku" {
  type    = string
  default = "PerGB2018"
}

variable "la_retenction_days" {
  type    = number
  default = 30
}

variable "subscription-id" {
  description = "Azure subscription ID"
}

variable "spn-client-id" {
  description = "Client ID of the service principal"
}

variable "spn-client-secret" {
  description = "Secret for service principal"
}

variable "spn-tenant-id" {
  description = "Tenant ID for service principal"
}
