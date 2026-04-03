# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the Aurora cluster (e.g. con-prod-use1-aurora-cluster)"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (e.g. 16.4, 17.4)"
  type        = string
}

variable "database_name" {
  description = "Name of the default database to create"
  type        = string
}

variable "master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password for the Aurora cluster (from Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "subnet_ids" {
  description = "List of private database subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs to attach to the cluster"
  type        = list(string)
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "platform"], var.env)
    error_message = "Environment must be one of: dev, staging, prod, platform."
  }
}

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "conservice"
}

# -----------------------------------------------------------------------------
# Preset System
# -----------------------------------------------------------------------------

variable "preset" {
  description = "Configuration preset: lean (dev), single (staging), or high-availability (prod)"
  type        = string
  default     = "lean"

  validation {
    condition     = contains(["lean", "single", "high-availability"], var.preset)
    error_message = "Must be lean, single, or high-availability."
  }
}

# -----------------------------------------------------------------------------
# Optional Overrides (override preset defaults)
# -----------------------------------------------------------------------------

variable "min_capacity" {
  description = "Minimum ACU capacity for Serverless v2 (overrides preset)"
  type        = number
  default     = null
}

variable "max_capacity" {
  description = "Maximum ACU capacity for Serverless v2 (overrides preset)"
  type        = number
  default     = null
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (overrides preset)"
  type        = number
  default     = null
}

variable "deletion_protection" {
  description = "Enable deletion protection (overrides preset)"
  type        = bool
  default     = null
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion (overrides preset)"
  type        = bool
  default     = null
}

variable "instance_count" {
  description = "Number of cluster instances (overrides preset)"
  type        = number
  default     = null
}

variable "instance_class" {
  description = "Instance class — db.serverless or db.r8g.* (overrides preset)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Maintenance & Backup Windows
# -----------------------------------------------------------------------------

variable "preferred_backup_window" {
  description = "Daily backup window in UTC (e.g. 03:00-04:00)"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window in UTC (e.g. sun:01:00-sun:02:00)"
  type        = string
  default     = "sun:01:00-sun:02:00"
}

# -----------------------------------------------------------------------------
# Monitoring & Logging
# -----------------------------------------------------------------------------

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on cluster instances"
  type        = bool
  default     = true
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types to export to CloudWatch (postgresql, upgrade)"
  type        = list(string)
  default     = ["postgresql"]
}

variable "enhanced_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 to disable, 1/5/10/15/30/60)"
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# Authentication
# -----------------------------------------------------------------------------

variable "iam_database_authentication_enabled" {
  description = "Enable IAM database authentication"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Parameter Overrides
# -----------------------------------------------------------------------------

variable "cluster_parameters" {
  description = "Additional cluster parameter group parameters"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "instance_parameters" {
  description = "Additional instance parameter group parameters"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
