variable "app_name" {
  description = "Application name (used in resource naming)"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "config_path" {
  description = "Path to the app's infra config directory (contains base.yaml, database.yaml, etc.)"
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
