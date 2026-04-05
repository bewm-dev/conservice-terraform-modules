variable "app_name" {
  description = "Application name (used in resource naming)"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "plat"], var.env)
    error_message = "env must be one of: dev, stg, prod, plat."
  }
}

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "resource_prefix" {
  description = "Abbreviated prefix for workload resource names"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption. If null, uses AWS-managed KMS key."
  type        = string
  default     = null
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
