# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Application name (used in resource naming)"
  type        = string
}

variable "project" {
  description = "Project name for S3 bucket and Secrets Manager naming"
  type        = string
  default     = "conservice"
}

variable "resource_prefix" {
  description = "Short prefix for workload resource naming"
  type        = string
  default     = "csvc"
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
  description = "Path to infra.yaml config directory. Set to null when using HCL variables directly."
  type        = string
  default     = null
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

# Pod Identity — required when pod_identity is defined in infra.yaml
variable "cluster_name" {
  description = "EKS cluster name for Pod Identity association"
  type        = string
  default     = ""
}

variable "aws_account_id" {
  description = "AWS account ID (used in IAM policy resource ARNs)"
  type        = string
  default     = ""
}

variable "enable_databases" {
  description = "Enable database provisioning (requires postgresql provider with VPC access to Aurora)"
  type        = bool
  default     = true
}

# CI Role — required when ci_role is defined in infra.yaml
variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in the org account (for CI role trust)"
  type        = string
  default     = "arn:aws:iam::896476316505:role/ci/conservice-org-github-actions-role"
}

variable "tf_state_bucket" {
  description = "S3 bucket name for Terraform state (CI role needs read/write)"
  type        = string
  default     = ""
}

variable "ecr_account_id" {
  description = "AWS account ID where ECR repos live (platform account)"
  type        = string
  default     = "626209130023"
}

variable "ecr_repos" {
  description = "List of ECR image names to create (e.g., [\"frontend\", \"dal\"]). Created as apps/{app_name}-{image} in the platform account via aws.ecr provider."
  type        = list(string)
  default     = []
}

variable "ecr_kms_key_arn" {
  description = "KMS key ARN in the platform account for ECR encryption. Required when ecr_repos is non-empty."
  type        = string
  default     = ""
}

variable "ecr_cross_account_ids" {
  description = "AWS account IDs that can pull from and push to these ECR repos (workload accounts)"
  type        = list(string)
  default     = []
}

variable "ecr_image_retention_count" {
  description = "Number of tagged images to retain per ECR repo"
  type        = number
  default     = 50
}

# -----------------------------------------------------------------------------
# HCL resource inputs — use these instead of config_path/infra.yaml
# When config_path is null, these are used directly.
# When config_path is set, infra.yaml takes precedence.
# -----------------------------------------------------------------------------

variable "team" {
  description = "Team name for tagging"
  type        = string
  default     = ""
}

variable "domain" {
  description = "Domain name for tagging"
  type        = string
  default     = ""
}

variable "portfolio" {
  description = "Portfolio name for tagging"
  type        = string
  default     = ""
}

variable "databases" {
  description = "Map of databases to create in shared Aurora cluster"
  type        = any
  default     = {}
}

variable "buckets" {
  description = "Map of S3 buckets to create"
  type        = any
  default     = {}
}

variable "queues" {
  description = "Map of SQS queues to create"
  type        = any
  default     = {}
}

variable "topics" {
  description = "Map of SNS topics to create"
  type        = any
  default     = {}
}

variable "secrets" {
  description = "Map of Secrets Manager secrets to create"
  type        = any
  default     = {}
}

variable "app_config_keys" {
  description = "Manual config key names for {app}/config. These get REPLACE_ME placeholders; populate real values via console/CLI after apply. Use UPPER_CASE — keys become env var names via ESO dataFrom.extract."
  type        = list(string)
  default     = []
}


variable "pod_identity" {
  description = "Pod Identity config: { namespace, service_account }. Null to skip."
  type        = any
  default     = null
}

variable "ci_role" {
  description = "CI role config: { github_org, repo_name }. Null to skip."
  type        = any
  default     = null
}

variable "temporal" {
  description = "Temporal Cloud config: { regions, retention_days, search_attributes, api_key_expiry, ... }. Null to skip."
  type        = any
  default     = null
}

variable "sso_access" {
  description = <<-EOT
    SSO Identity Center access config. Null to skip.
    When set, creates SSO account assignments for the app's Google groups
    via cross-account assume to the org account.
    {
      admin_group    = string       # Google group name for DB admin (e.g., "awsgf-rates-agent-admin")
      readonly_group = string       # Google group name for DB readonly (e.g., "awsgf-rates-agent-readonly")
      account_ids    = list(string) # Workload account IDs to assign access to
    }
    Requires: aws.org provider configured with assume_role to the org SSO assignment role.
  EOT
  type        = any
  default     = null
}

variable "sso_instance_arn" {
  description = "SSO instance ARN (from identity-center outputs). Required when sso_access is set."
  type        = string
  default     = ""
}

variable "identity_store_id" {
  description = "Identity Store ID (from identity-center outputs). Required when sso_access is set."
  type        = string
  default     = ""
}

variable "bedrock" {
  description = <<-EOT
    Bedrock AI model access config. Null to skip. Adds Bedrock permissions to the Pod Identity role.
    {
      model_ids       = list(string)  # Required: Bedrock model IDs (e.g., ["anthropic.claude-sonnet-4-20250514"])
      knowledge_bases = bool          # Optional: allow Knowledge Base APIs (default: false)
      guardrails      = bool          # Optional: allow ApplyGuardrail API (default: false)
    }
  EOT
  type        = any
  default     = null
}
