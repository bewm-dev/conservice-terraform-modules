# =============================================================================
# conservice-vpc-network
#
# Complete spoke-account networking: VPC + security groups + TGW connectivity.
# Naming: conservice-{env}-{region}-{resource}
# =============================================================================

locals {
  region_codes = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-1"      = "usw1"
    "us-west-2"      = "usw2"
    "eu-west-1"      = "euw1"
    "eu-central-1"   = "euc1"
    "ap-southeast-1" = "apse1"
  }
  region_code = local.region_codes[var.aws_region]
  name_prefix = "conservice-${var.env}-${local.region_code}"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../aws-vpc"

  env                     = var.env
  project                 = var.project
  aws_region              = var.aws_region
  vpc_cidr                = var.vpc_cidr
  azs                     = var.azs
  cluster_name            = var.cluster_name
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention      = var.flow_log_retention
  enable_vpc_endpoints    = var.enable_vpc_endpoints
  interface_vpc_endpoints = var.interface_vpc_endpoints
  tags                    = var.tags
}

# -----------------------------------------------------------------------------
# Transit Gateway Attachment
# -----------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.transit_gateway_id != null ? 1 : 0

  subnet_ids         = module.vpc.private_app_subnet_ids
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-tgw-attachment"
  })
}

# -----------------------------------------------------------------------------
# Transit Gateway Routes — Private App Subnets
# -----------------------------------------------------------------------------

resource "aws_route" "private_app_tgw_rfc1918_10" {
  for_each = var.transit_gateway_id != null ? module.vpc.private_app_route_table_ids : {}

  route_table_id         = each.value
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "private_app_tgw_rfc1918_172" {
  for_each = var.transit_gateway_id != null ? module.vpc.private_app_route_table_ids : {}

  route_table_id         = each.value
  destination_cidr_block = "172.16.0.0/12"
  transit_gateway_id     = var.transit_gateway_id
}

# -----------------------------------------------------------------------------
# Transit Gateway Routes — Private DB Subnets
# -----------------------------------------------------------------------------

resource "aws_route" "private_db_tgw_rfc1918_10" {
  for_each = var.transit_gateway_id != null ? module.vpc.private_db_route_table_ids : {}

  route_table_id         = each.value
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "private_db_tgw_rfc1918_172" {
  for_each = var.transit_gateway_id != null ? module.vpc.private_db_route_table_ids : {}

  route_table_id         = each.value
  destination_cidr_block = "172.16.0.0/12"
  transit_gateway_id     = var.transit_gateway_id
}

# -----------------------------------------------------------------------------
# Security Group — EKS Cluster Additional
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster_additional" {
  count = var.create_eks_sg ? 1 : 0

  name        = "${local.name_prefix}-eks-cluster-additional"
  description = "Additional security group for EKS cluster API access"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-additional"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_https_from_vpc" {
  count = var.create_eks_sg ? 1 : 0

  security_group_id = aws_security_group.eks_cluster_additional[0].id
  description       = "HTTPS from VPC CIDR"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "eks_https_from_internal" {
  count = var.create_eks_sg ? 1 : 0

  security_group_id = aws_security_group.eks_cluster_additional[0].id
  description       = "HTTPS from internal CIDRs (cross-account via TGW)"
  prefix_list_id    = var.internal_prefix_list_id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "eks_all_outbound" {
  count = var.create_eks_sg ? 1 : 0

  security_group_id = aws_security_group.eks_cluster_additional[0].id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# Security Group — Aurora
# -----------------------------------------------------------------------------

resource "aws_security_group" "aurora" {
  count = var.create_aurora_sg ? 1 : 0

  name        = "${local.name_prefix}-aurora"
  description = "Security group for Aurora PostgreSQL clusters"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-aurora"
  })
}

resource "aws_vpc_security_group_ingress_rule" "aurora_postgres_from_vpc" {
  count = var.create_aurora_sg ? 1 : 0

  security_group_id = aws_security_group.aurora[0].id
  description       = "PostgreSQL from VPC CIDR"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "aurora_all_outbound" {
  count = var.create_aurora_sg ? 1 : 0

  security_group_id = aws_security_group.aurora[0].id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# Security Group — Internal
# -----------------------------------------------------------------------------

resource "aws_security_group" "internal" {
  name        = "${local.name_prefix}-internal"
  description = "Internal traffic within VPC and cross-account via TGW"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-internal"
  })
}

resource "aws_vpc_security_group_ingress_rule" "internal_from_vpc" {
  security_group_id = aws_security_group.internal.id
  description       = "All traffic from VPC CIDR"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "internal_from_prefix_list" {
  security_group_id = aws_security_group.internal.id
  description       = "All traffic from internal CIDRs (cross-account via TGW)"
  prefix_list_id    = var.internal_prefix_list_id
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "internal_all_outbound" {
  security_group_id = aws_security_group.internal.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
