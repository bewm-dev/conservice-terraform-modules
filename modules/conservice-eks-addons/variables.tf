# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for resource ARN construction"
  type        = string
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

# -----------------------------------------------------------------------------
# Optional Configuration
# -----------------------------------------------------------------------------

variable "route53_zone_ids" {
  description = "List of Route53 hosted zone IDs to scope External DNS access (empty = all zones)"
  type        = list(string)
  default     = []
}
