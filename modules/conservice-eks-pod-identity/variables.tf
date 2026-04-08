# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, staging, prod, platform)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "plat"], var.env)
    error_message = "Environment must be one of: dev, stg, prod, plat."
  }
}

variable "aws_account_id" {
  description = "AWS account ID for resource ARN construction"
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit number"
  }
}

# -----------------------------------------------------------------------------
# Service Toggles
# -----------------------------------------------------------------------------

variable "enable_lbc" {
  description = "Enable AWS Load Balancer Controller Pod Identity"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable External DNS Pod Identity"
  type        = bool
  default     = true
}

variable "enable_eso" {
  description = "Enable External Secrets Operator Pod Identity"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights Pod Identity"
  type        = bool
  default     = true
}

variable "enable_kargo" {
  description = "Enable Kargo ECR image discovery Pod Identity"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Optional Configuration
# -----------------------------------------------------------------------------

variable "route53_zone_ids" {
  description = "List of Route53 hosted zone IDs to scope External DNS access. Required when enable_external_dns is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_external_dns || length(var.route53_zone_ids) > 0
    error_message = "route53_zone_ids must not be empty when enable_external_dns is true."
  }
}

variable "route53_cross_account_role_arn" {
  description = "IAM role ARN in the DNS account for ExternalDNS cross-account Route53 access. Empty = same account."
  type        = string
  default     = ""
}

variable "secrets_kms_key_arns" {
  description = "KMS key ARNs used to encrypt Secrets Manager secrets. ESO needs kms:Decrypt to read secret values."
  type        = list(string)
  default     = []
}
