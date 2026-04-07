# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "database_name" {
  description = "Name of the PostgreSQL database to create"
  type        = string
}

variable "service_role" {
  description = "Name of the IAM-authenticated role for the application service"
  type        = string
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "team_role" {
  description = "Name of the IAM-authenticated read-only role for the dev team. Empty string to skip."
  type        = string
  default     = ""
}

variable "app_permissions" {
  description = "Table-level privileges for the service role"
  type        = list(string)
  default     = ["SELECT", "INSERT", "UPDATE", "DELETE"]
}

variable "team_permissions" {
  description = "Table-level privileges for the team role"
  type        = list(string)
  default     = ["SELECT"]
}

variable "additional_readonly_roles" {
  description = "Additional IAM-authenticated read-only roles (e.g., cross-team access or reporting)"
  type        = list(string)
  default     = []
}

variable "admin_groups" {
  description = "Identity Center group names for admin access. Each group becomes a shared PostgreSQL role with full database access via IAM auth."
  type        = list(string)
  default     = []
}

variable "readonly_groups" {
  description = "Identity Center group names for read-only access. Each group becomes a shared PostgreSQL role with SELECT-only access via IAM auth."
  type        = list(string)
  default     = []
}

variable "admin_users" {
  description = "Individual admin users (Google identity usernames). Each gets a personal login with full database access. Prefer admin_groups for team access."
  type        = list(string)
  default     = []
}

variable "readonly_users" {
  description = "Individual read-only users (Google identity usernames). Each gets a personal login with SELECT-only access. Prefer readonly_groups for team access."
  type        = list(string)
  default     = []
}

variable "extensions" {
  description = "PostgreSQL extensions to enable (e.g., [\"pgcrypto\", \"uuid-ossp\"])"
  type        = list(string)
  default     = []
}

variable "connection_limit" {
  description = "Maximum concurrent connections. -1 for unlimited."
  type        = number
  default     = -1
}

variable "encoding" {
  description = "Character set encoding"
  type        = string
  default     = "UTF8"
}

variable "lc_collate" {
  description = "Collation order"
  type        = string
  default     = "en_US.UTF-8"
}

variable "lc_ctype" {
  description = "Character classification"
  type        = string
  default     = "en_US.UTF-8"
}
