# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Application name (used in resource naming)"
  type        = string
}

variable "env" {
  description = "Environment: dev, stg, prod, plat"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "plat"], var.env)
    error_message = "env must be one of: dev, stg, prod, plat."
  }
}

variable "region" {
  description = "AWS region (e.g., us-east-1). Used for region code in naming."
  type        = string

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.region)
    error_message = "region must be one of: us-east-1, us-east-2, us-west-1, us-west-2."
  }
}

variable "config_path" {
  description = "Path to the app's infra config directory (contains base.yaml and optional resource YAML files)"
  type        = string
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "KMS key ARN for S3/SNS encryption. If null, uses AWS-managed keys."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
