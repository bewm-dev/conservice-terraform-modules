# -----------------------------------------------------------------------------
# Conservice Account Base — Variables
# -----------------------------------------------------------------------------

variable "env" {
  description = "Environment name (dev, staging, prod, tools)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for this account"
  type        = string
}

variable "tools_account_id" {
  description = "AWS account ID for the tools account (required when role_type = cross-account)"
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
