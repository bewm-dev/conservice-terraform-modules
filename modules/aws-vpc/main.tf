# -----------------------------------------------------------------------------
# Conservice AWS VPC Module
#
# Creates a VPC with public, private (app), and private (database) subnets
# across specified AZs. Includes IGW, NAT Gateway, route tables, flow logs,
# and optional VPC endpoints.
#
# Naming: conservice-{env}-{resource}
# -----------------------------------------------------------------------------

locals {
  name_prefix = "conservice-${var.env}"

  # Calculate subnet CIDRs from the VPC CIDR
  # Split the VPC CIDR into /20 blocks for private-app, /22 for private-db, /24 for public
  vpc_cidr_bits  = tonumber(split("/", var.vpc_cidr)[1])
  private_app_newbits = var.private_app_subnet_bits - local.vpc_cidr_bits
  private_db_newbits  = var.private_db_subnet_bits - local.vpc_cidr_bits
  public_newbits      = var.public_subnet_bits - local.vpc_cidr_bits

  # Generate subnet CIDRs if not explicitly provided
  private_app_subnets = length(var.private_app_subnets) > 0 ? var.private_app_subnets : [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, local.private_app_newbits, i)
  ]

  private_db_subnets = length(var.private_db_subnets) > 0 ? var.private_db_subnets : [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, local.private_db_newbits, i + length(var.azs))
  ]

  public_subnets = length(var.public_subnets) > 0 ? var.public_subnets : [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, local.public_newbits, i + (length(var.azs) * 4))
  ]
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public Subnets
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = { for i, az in var.azs : az => {
    cidr = local.public_subnets[i]
    az   = az
  } }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                = "${local.name_prefix}-public-${each.key}"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/conservice-${var.env}-workload" = "shared"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-rtb"
  })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# NAT Gateway (single or per-AZ)
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = var.single_nat_gateway ? { (var.azs[0]) = var.azs[0] } : { for az in var.azs : az => az }

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = aws_eip.nat

  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# Private App Subnets
# -----------------------------------------------------------------------------

resource "aws_subnet" "private_app" {
  for_each = { for i, az in var.azs : az => {
    cidr = local.private_app_subnets[i]
    az   = az
  } }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(var.tags, {
    Name                                = "${local.name_prefix}-private-app-${each.key}"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/conservice-${var.env}-workload" = "shared"
    "karpenter.sh/discovery"            = "conservice-${var.env}-workload"
  })
}

resource "aws_route_table" "private_app" {
  for_each = { for az in var.azs : az => az }

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-app-rtb-${each.key}"
  })
}

resource "aws_route" "private_app_nat" {
  for_each = aws_route_table.private_app

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[var.azs[0]].id : aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private_app" {
  for_each = aws_subnet.private_app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app[each.key].id
}

# -----------------------------------------------------------------------------
# Private Database Subnets
# -----------------------------------------------------------------------------

resource "aws_subnet" "private_db" {
  for_each = { for i, az in var.azs : az => {
    cidr = local.private_db_subnets[i]
    az   = az
  } }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-db-${each.key}"
  })
}

resource "aws_route_table" "private_db" {
  for_each = { for az in var.azs : az => az }

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-db-rtb-${each.key}"
  })
}

resource "aws_route" "private_db_nat" {
  for_each = aws_route_table.private_db

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[var.azs[0]].id : aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private_db" {
  for_each = aws_subnet.private_db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_db[each.key].id
}

# -----------------------------------------------------------------------------
# DB Subnet Group (for Aurora/RDS)
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private_db : s.id]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# -----------------------------------------------------------------------------
# VPC Flow Logs
# -----------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log[0].arn
  iam_role_arn         = aws_iam_role.flow_log[0].arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-flow-log"
  })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/vpc/${local.name_prefix}-flow-log"
  retention_in_days = var.flow_log_retention

  tags = var.tags
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-vpc-flow-log"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-vpc-flow-log"
  role = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

# -----------------------------------------------------------------------------
# VPC Endpoints (Gateway — free)
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = concat(
    [for rt in aws_route_table.private_app : rt.id],
    [for rt in aws_route_table.private_db : rt.id],
  )

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"

  route_table_ids = concat(
    [for rt in aws_route_table.private_app : rt.id],
    [for rt in aws_route_table.private_db : rt.id],
  )

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-dynamodb"
  })
}

# -----------------------------------------------------------------------------
# VPC Endpoints (Interface — cost per hour + per GB)
# -----------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints && length(var.interface_vpc_endpoints) > 0 ? 1 : 0

  name        = "${local.name_prefix}-vpce-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? toset(var.interface_vpc_endpoints) : toset([])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.private_app : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-${each.key}"
  })
}
