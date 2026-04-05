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

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role (used for Karpenter iam:PassRole)"
  type        = string
}

# -----------------------------------------------------------------------------
# Addon Toggles
# -----------------------------------------------------------------------------

variable "enable_lbc" {
  description = "Enable AWS Load Balancer Controller resources"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable External DNS resources"
  type        = bool
  default     = true
}

variable "enable_eso" {
  description = "Enable External Secrets Operator resources"
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Enable Karpenter resources"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights (OTEL-based observability)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Optional Configuration
# -----------------------------------------------------------------------------

variable "route53_zone_ids" {
  description = "List of Route53 hosted zone IDs to scope External DNS access (empty = all zones)"
  type        = list(string)
  default     = []
}
