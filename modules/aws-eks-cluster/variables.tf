variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
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
  description = "IAM role ARN for EKS managed node groups. If null, no EC2_LINUX access entry is created."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "KMS key ARN for EKS secrets encryption. If null, secrets encryption is disabled."
  type        = string
  default     = null
}

variable "cluster_admin_arns" {
  description = "IAM ARNs granted cluster admin access via EKS access entries"
  type        = list(string)
  default     = []
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server is accessible from the internet"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint. Only applies when endpoint_public_access is true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to the EKS cluster"
  type        = list(string)
  default     = []
}

variable "env" {
  description = "Environment name (e.g., dev, staging, prod, platform)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "platform"], var.env)
    error_message = "Environment must be one of: dev, staging, prod, platform."
  }
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
