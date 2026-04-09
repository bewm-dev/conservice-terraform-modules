# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Application name (used in resource naming and tagging)"
  type        = string
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

variable "resource_prefix" {
  description = "Short prefix for workload resource naming"
  type        = string
  default     = "csvc"
}

variable "aws_account_id" {
  description = "AWS account ID (used in IAM policy resource ARNs)"
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit number."
  }
}

# -----------------------------------------------------------------------------
# Bedrock Model Access
# -----------------------------------------------------------------------------

variable "model_ids" {
  description = "List of Bedrock model IDs to allow invocation (e.g., ['anthropic.claude-sonnet-4-20250514', 'amazon.titan-embed-text-v2:0'])"
  type        = list(string)

  validation {
    condition     = length(var.model_ids) > 0
    error_message = "At least one model_id must be specified."
  }
}

variable "enable_knowledge_bases" {
  description = "Allow Bedrock Knowledge Bases API access (Retrieve, RetrieveAndGenerate)"
  type        = bool
  default     = false
}

variable "knowledge_base_ids" {
  description = "List of specific Knowledge Base IDs to allow. Empty list allows all KBs in the account."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Guardrails
# -----------------------------------------------------------------------------

variable "enable_guardrails" {
  description = "Create a Bedrock Guardrail for this application"
  type        = bool
  default     = false
}

variable "guardrail_config" {
  description = <<-EOT
    Guardrail configuration. Only used when enable_guardrails = true.
    {
      blocked_input_messaging  = string  # Message shown when input is blocked
      blocked_output_messaging = string  # Message shown when output is blocked
      pii_action               = string  # "BLOCK" or "ANONYMIZE"
      pii_types                = list    # PII entity types to filter (e.g., ["EMAIL", "PHONE", "SSN", "US_SOCIAL_SECURITY_NUMBER"])
      content_filters          = list    # Content filter configs [{type, input_strength, output_strength}]
    }
  EOT
  type        = any
  default     = {}
}

# -----------------------------------------------------------------------------
# Model Invocation Logging
# -----------------------------------------------------------------------------

variable "enable_invocation_logging" {
  description = "Enable Bedrock model invocation logging to S3 and/or CloudWatch"
  type        = bool
  default     = false
}

variable "logging_s3_bucket_arn" {
  description = "S3 bucket ARN for model invocation logs. Required when enable_invocation_logging = true."
  type        = string
  default     = ""
}

variable "logging_s3_key_prefix" {
  description = "S3 key prefix for model invocation logs"
  type        = string
  default     = "bedrock-logs"
}

variable "enable_cloudwatch_logging" {
  description = "Also send invocation logs to CloudWatch Logs"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 90
}

# -----------------------------------------------------------------------------
# EKS Pod Identity Integration
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name for Pod Identity association. Empty to skip."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace for Pod Identity association"
  type        = string
  default     = ""
}

variable "service_account" {
  description = "Kubernetes service account for Pod Identity association"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# AI Tagging (Cost Attribution)
# -----------------------------------------------------------------------------

variable "ai_model" {
  description = "Primary AI model name for cost attribution tagging (e.g., 'claude-sonnet-4')"
  type        = string
}

variable "ai_use_case" {
  description = "AI use case for cost attribution (e.g., 'rag', 'chat', 'embeddings', 'classification')"
  type        = string
}

variable "ai_cost_group" {
  description = "AI cost grouping — typically matches app_name but can group multiple apps"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags applied to all resources (merged with AI tags and provider default_tags)"
  type        = map(string)
  default     = {}
}
