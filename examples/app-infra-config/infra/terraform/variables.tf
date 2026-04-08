# Per-environment values — set in envs/{env}/terraform.tfvars
variable "env" {
  description = "Environment: dev, stg, prod"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name for Pod Identity"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

# Aurora connection — injected by CI from Secrets Manager
variable "aurora_host" {
  type = string
}

variable "aurora_master_username" {
  type      = string
  sensitive = true
}

variable "aurora_master_password" {
  type      = string
  sensitive = true
}
