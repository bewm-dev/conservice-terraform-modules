# -----------------------------------------------------------------------------
# Required Variables
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
# Optional Variables
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
  description = "Additional IAM-authenticated read-only roles (e.g., for cross-team access or reporting)"
  type        = list(string)
  default     = []
}

variable "admin_users" {
  description = "Individual IAM-authenticated admin users (Google identity usernames, e.g., [\"aarondavis\", \"jane.smith\"]). Each gets a personal login role with full database access."
  type        = list(string)
  default     = []
}

variable "readonly_users" {
  description = "Individual IAM-authenticated read-only users (Google identity usernames). Each gets a personal login role with SELECT-only access."
  type        = list(string)
  default     = []
}

variable "extensions" {
  description = "PostgreSQL extensions to enable in the database (e.g., [\"pgcrypto\", \"uuid-ossp\", \"pg_stat_statements\"])"
  type        = list(string)
  default     = []
}

variable "connection_limit" {
  description = "Maximum number of concurrent connections to the database. -1 for unlimited."
  type        = number
  default     = -1
}

variable "encoding" {
  description = "Character set encoding for the database"
  type        = string
  default     = "UTF8"
}

variable "lc_collate" {
  description = "Collation order for the database"
  type        = string
  default     = "en_US.UTF-8"
}

variable "lc_ctype" {
  description = "Character classification for the database"
  type        = string
  default     = "en_US.UTF-8"
}
