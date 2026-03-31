variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster ENIs"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS cluster service role"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS managed node groups"
  type        = string
}

variable "cluster_additional_security_group_ids" {
  description = "Additional security group IDs to attach to the EKS cluster"
  type        = list(string)
  default     = []
}

variable "cluster_encryption_config" {
  description = "Encryption configuration for EKS secrets"
  type = object({
    provider_key_arn = string
    resources        = list(string)
  })
  default = null
}

variable "env" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name for resource tagging"
  type        = string
}

variable "cluster_enabled_log_types" {
  description = "List of EKS cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
