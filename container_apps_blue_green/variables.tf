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
  description = "Client secret of the service principal"
  sensitive   = true
}

variable "spn-tenant-id" {
  description = "Tenant ID of the service principal"
}

variable "production_label" {
  description = "Which revision label receives 100% of production traffic: 'blue' or 'green'."
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.production_label)
    error_message = "production_label must be either 'blue' or 'green'."
  }
}

variable "enable_blue_green" {
  description = <<-EOT
    Enable blue-green traffic splitting. Set to false for first deployment
    (single revision), then set to true after both revisions exist.
  EOT
  type        = bool
  default     = false
}

variable "blue_revision_suffix" {
  description = "Deterministic revision suffix for the blue environment (e.g. commit hash or build ID)."
  type        = string
  default     = "blue-v1"
}

variable "green_revision_suffix" {
  description = "Deterministic revision suffix for the green environment (e.g. commit hash or build ID)."
  type        = string
  default     = "green-v1"
}

variable "blue_image" {
  description = "Container image tag deployed to the blue revision."
  type        = string
}

variable "green_image" {
  description = "Container image tag deployed to the green revision."
  type        = string
  default     = ""
}
