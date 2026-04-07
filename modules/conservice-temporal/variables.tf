# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Application name (used in namespace naming: {app_name}-{env})"
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

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

variable "regions" {
  description = "Temporal Cloud regions for the namespace (e.g., [\"aws-us-east-1\"]). Requires cloud provider prefix."
  type        = list(string)
  default     = ["aws-us-east-1"]
}

variable "retention_days" {
  description = "Workflow execution history retention in days"
  type        = number
  default     = 30
}

variable "api_key_auth" {
  description = "Enable API key authentication on the namespace"
  type        = bool
  default     = true
}

variable "enable_delete_protection" {
  description = "Prevent accidental namespace deletion (recommend true for prod)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Search Attributes
# -----------------------------------------------------------------------------

variable "search_attributes" {
  description = "Map of custom search attributes: { name = type }. Valid types: bool, datetime, double, int, keyword, keyword_list, text"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for type in values(var.search_attributes) :
      contains(["bool", "datetime", "double", "int", "keyword", "keyword_list", "text"], lower(type))
    ])
    error_message = "Search attribute types must be one of: bool, datetime, double, int, keyword, keyword_list, text."
  }
}

# -----------------------------------------------------------------------------
# Service Account + API Key
# -----------------------------------------------------------------------------

variable "create_service_account" {
  description = "Create a namespace-scoped service account with an API key"
  type        = bool
  default     = true
}

variable "service_account_permission" {
  description = "Namespace permission for the service account: admin, write, read"
  type        = string
  default     = "write"

  validation {
    condition     = contains(["admin", "write", "read"], var.service_account_permission)
    error_message = "service_account_permission must be one of: admin, write, read."
  }
}

variable "api_key_expiry" {
  description = "API key expiry time in ISO 8601 format (e.g., 2027-04-01T00:00:00Z)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Secrets Manager — store the API key token
# -----------------------------------------------------------------------------

variable "store_api_key_in_secrets_manager" {
  description = "Store the generated API key token in AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN for encrypting the Secrets Manager secret. Null uses AWS-managed key."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags applied to AWS resources (Secrets Manager)"
  type        = map(string)
  default     = {}
}
