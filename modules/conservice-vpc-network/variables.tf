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

variable "project" {
  description = "Project name for tagging"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Transit Gateway
# -----------------------------------------------------------------------------

variable "transit_gateway_id" {
  description = "Transit Gateway ID for cross-account connectivity. Set to null to skip TGW attachment and routes."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# VPC Options
# -----------------------------------------------------------------------------

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost savings for non-prod)"
  type        = bool
  default     = true
}

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

variable "enable_vpc_endpoints" {
  description = "Enable VPC gateway endpoints (S3, DynamoDB) and optional interface endpoints"
  type        = bool
  default     = true
}

variable "interface_vpc_endpoints" {
  description = "List of AWS services for interface VPC endpoints"
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "secretsmanager", "logs", "ec2", "eks-auth", "elasticloadbalancing", "ssm", "autoscaling", "kinesis-firehose"]
}

# -----------------------------------------------------------------------------
# Security Group Toggles
# -----------------------------------------------------------------------------

variable "internal_prefix_list_id" {
  description = "ID of the shared managed prefix list for internal CIDRs. If set, security groups use this instead of hardcoded CIDRs."
  type        = string
  default     = ""
}

variable "create_eks_sg" {
  description = "Create the EKS cluster additional security group"
  type        = bool
  default     = true
}

variable "create_aurora_sg" {
  description = "Create the Aurora database security group"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
