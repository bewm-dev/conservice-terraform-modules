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
  description = <<-EOT
    Whether to actually provision PostgreSQL databases + IAM-auth roles declared in `databases`.
    Requires a `postgresql` provider configured in the caller's provider.tf with Aurora
    cluster admin credentials. Off by default so apps can declare `databases = {...}` for
    documentation / IAM purposes while SRE still owns the provider wiring.
    Flip to true once the postgresql provider is wired and Aurora admin creds are available.
  EOT
  type        = bool
  default     = false
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

# ECR repos are managed centrally in the platform account's ECR component.
# See conservice-aws-platform/accounts/platform/global/ecr/
# The CI role still needs ECR push permissions (scoped to this app's repos).

variable "ecr_account_id" {
  description = "AWS account ID where ECR repos live (platform account). Used for CI role ECR push policy."
  type        = string
  default     = "626209130023"
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

  validation {
    condition = alltrue([
      for _, db in var.databases : alltrue([
        for k in keys(db) : contains([
          "service_role", "team_role", "extensions",
          "app_permissions", "team_permissions",
          "admin_groups", "readonly_groups",
          "admin_users", "readonly_users",
          "connection_limit", "additional_readonly_roles"
        ], k)
      ])
    ])
    error_message = "databases: unknown key in a database entry. Valid per-db keys: service_role, team_role, extensions, app_permissions, team_permissions, admin_groups, readonly_groups, admin_users, readonly_users, connection_limit, additional_readonly_roles. Note: 'engine' is NOT valid (always aurora-postgresql)."
  }
}

variable "buckets" {
  description = "Map of S3 buckets to create"
  type        = any
  default     = {}
}

variable "s3_force_destroy" {
  description = "Allow terraform destroy to delete non-empty S3 buckets. Required for clean teardown."
  type        = bool
  default     = true
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

variable "event_buses" {
  description = "Map of EventBridge event buses to create. Each bus can contain rules: { rules = { rule_name = { pattern = {...}, description = \"...\" } } }"
  type        = any
  default     = {}
}

variable "state_machines" {
  description = "Map of Step Functions state machines to create. Each: { type = \"STANDARD\"|\"EXPRESS\", definition = \"...\", log_level = \"ALL\", log_retention_days = 30 }"
  type        = any
  default     = {}
}

variable "tables" {
  description = "Map of DynamoDB tables to create. Each: { hash_key, hash_key_type = \"S\", range_key, range_key_type = \"S\", billing_mode = \"PAY_PER_REQUEST\", gsi = {...}, ttl_attribute, point_in_time_recovery = true }"
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

variable "secrets_recovery_window_days" {
  description = "Days before a deleted secret is permanently removed. 0 = immediate deletion (clean teardown). 7-30 = recovery window."
  type        = number
  default     = 0
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

  validation {
    condition = var.temporal == null || alltrue([
      for k in keys(var.temporal) : contains([
        "regions", "retention_days", "search_attributes", "api_key_expiry",
        "api_key_auth", "enable_delete_protection", "create_service_account",
        "service_account_permission", "store_api_key_in_secrets_manager"
      ], k)
    ])
    error_message = "temporal: unknown key. 'namespace' and 'enabled' are NOT valid — the namespace is derived from app_name, and setting the block non-null is how you opt in. Valid keys: regions, retention_days, search_attributes, api_key_expiry, api_key_auth, enable_delete_protection, create_service_account, service_account_permission, store_api_key_in_secrets_manager."
  }
}

# SSO Identity Center — per-app permission sets + assignments are managed
# centrally in the org account's identity-center module, not here.
# See conservice-aws-platform/accounts/organization/global/identity-center/

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

  validation {
    condition = var.bedrock == null || alltrue([
      for k in keys(var.bedrock) : contains(["model_ids", "knowledge_bases", "guardrails"], k)
    ])
    error_message = "bedrock: unknown key. 'enabled' and 'models' are NOT valid — the block being non-null is the opt-in, and the model list key is 'model_ids' (plural+underscore). Valid keys: model_ids, knowledge_bases, guardrails."
  }

  validation {
    condition     = var.bedrock == null || can(tolist(lookup(var.bedrock, "model_ids", null)))
    error_message = "bedrock.model_ids is required when bedrock is set, and must be a list of strings (e.g., [\"anthropic.claude-sonnet-4-20250514\"])."
  }

  validation {
    condition     = var.bedrock == null || length(lookup(var.bedrock, "model_ids", [])) > 0
    error_message = "bedrock.model_ids must be a non-empty list. An empty or missing list means the Pod Identity role has no Bedrock InvokeModel permission — the app will get AccessDenied at runtime."
  }
}
