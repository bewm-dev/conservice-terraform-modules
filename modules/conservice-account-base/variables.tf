# -----------------------------------------------------------------------------
# Conservice Account Base — Variables
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "resource_prefix" {
  description = "Abbreviated prefix for workload resource names"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "plat", "org", "security", "log-archive"], var.env)
    error_message = "env must be one of: dev, stg, prod, plat, org, security, log-archive"
  }
}

variable "aws_account_id" {
  description = "AWS account ID for this account"
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit number"
  }
}

variable "platform_account_id" {
  description = "AWS account ID for the platform account (required when role_type = cross-account)"
  type        = string
  default     = null
}

variable "role_type" {
  description = "Trust model for the TF execution role: cross-account or self-contained"
  type        = string
  default     = "cross-account"

  validation {
    condition     = contains(["cross-account", "self-contained"], var.role_type)
    error_message = "role_type must be \"cross-account\" or \"self-contained\"."
  }
}

variable "enable_aurora_role" {
  description = "Create the Aurora access IAM role"
  type        = bool
  default     = true
}

variable "enable_ecr_pull_role" {
  description = "Create the ECR cross-account pull IAM role"
  type        = bool
  default     = true
}
