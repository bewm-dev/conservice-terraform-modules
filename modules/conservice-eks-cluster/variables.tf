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
    condition     = contains(["dev", "staging", "prod", "platform"], var.env)
    error_message = "Environment must be one of: dev, staging, prod, platform."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role for the EKS cluster control plane"
  type        = string
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "node_role_arn" {
  description = "ARN of the IAM role for EKS managed node groups"
  type        = string
  default     = null
}

variable "cluster_admin_arns" {
  description = "List of IAM ARNs granted cluster admin access"
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to the EKS cluster"
  type        = list(string)
  default     = []
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "kms_deletion_window" {
  description = "Number of days before KMS key deletion (7-30)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
