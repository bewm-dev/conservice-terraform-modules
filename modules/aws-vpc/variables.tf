# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "env" {
  description = "Environment name (e.g., dev, staging, prod, platform)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "platform"], var.env)
    error_message = "Environment must be one of: dev, staging, prod, platform."
  }
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of availability zones (e.g., [\"us-east-1a\", \"us-east-1b\", \"us-east-1c\"])"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region for VPC endpoint service names"
  type        = string
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "conservice"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Subnet CIDRs (override auto-calculation)
# -----------------------------------------------------------------------------

variable "private_app_subnets" {
  description = "Explicit CIDR blocks for private app subnets. If empty, auto-calculated from vpc_cidr."
  type        = list(string)
  default     = []
}

variable "private_db_subnets" {
  description = "Explicit CIDR blocks for private database subnets. If empty, auto-calculated from vpc_cidr."
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "Explicit CIDR blocks for public subnets. If empty, auto-calculated from vpc_cidr."
  type        = list(string)
  default     = []
}

variable "private_app_subnet_bits" {
  description = "Subnet mask bits for auto-calculated private app subnets (e.g., 19 for /19)"
  type        = number
  default     = 19
}

variable "private_db_subnet_bits" {
  description = "Subnet mask bits for auto-calculated private database subnets (e.g., 22 for /22)"
  type        = number
  default     = 22
}

variable "public_subnet_bits" {
  description = "Subnet mask bits for auto-calculated public subnets (e.g., 24 for /24)"
  type        = number
  default     = 24
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost savings for non-prod). Set false for HA in production."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Flow Logs
# -----------------------------------------------------------------------------

variable "enable_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch"
  type        = bool
  default     = true
}

variable "flow_log_retention" {
  description = "CloudWatch log group retention in days for flow logs"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# VPC Endpoints
# -----------------------------------------------------------------------------

variable "enable_vpc_endpoints" {
  description = "Enable VPC gateway endpoints (S3, DynamoDB) and optional interface endpoints"
  type        = bool
  default     = true
}

variable "interface_vpc_endpoints" {
  description = "List of AWS services for interface VPC endpoints (e.g., [\"ecr.api\", \"ecr.dkr\", \"sts\", \"secretsmanager\", \"logs\"])"
  type        = list(string)
  default     = []
}
