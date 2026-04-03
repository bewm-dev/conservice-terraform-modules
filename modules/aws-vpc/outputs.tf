# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_app_subnet_ids" {
  description = "List of private app subnet IDs (EKS, services)"
  value       = [for s in aws_subnet.private_app : s.id]
}

output "private_db_subnet_ids" {
  description = "List of private database subnet IDs (Aurora, RDS)"
  value       = [for s in aws_subnet.private_db : s.id]
}

output "public_subnet_cidrs" {
  description = "Map of AZ to public subnet CIDR"
  value       = { for az, s in aws_subnet.public : az => s.cidr_block }
}

output "private_app_subnet_cidrs" {
  description = "Map of AZ to private app subnet CIDR"
  value       = { for az, s in aws_subnet.private_app : az => s.cidr_block }
}

output "private_db_subnet_cidrs" {
  description = "Map of AZ to private database subnet CIDR"
  value       = { for az, s in aws_subnet.private_db : az => s.cidr_block }
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_app_route_table_ids" {
  description = "Map of AZ to private app route table ID (for adding TGW routes)"
  value       = { for az, rt in aws_route_table.private_app : az => rt.id }
}

output "private_db_route_table_ids" {
  description = "Map of AZ to private database route table ID (for adding TGW routes)"
  value       = { for az, rt in aws_route_table.private_db : az => rt.id }
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------

output "nat_gateway_ids" {
  description = "Map of AZ to NAT Gateway ID"
  value       = { for az, nat in aws_nat_gateway.this : az => nat.id }
}

output "nat_public_ips" {
  description = "Map of AZ to NAT Gateway public IP"
  value       = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

output "db_subnet_group_name" {
  description = "Name of the DB subnet group (for Aurora/RDS)"
  value       = aws_db_subnet_group.this.name
}

# -----------------------------------------------------------------------------
# Misc
# -----------------------------------------------------------------------------

output "igw_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "name_prefix" {
  description = "The naming prefix used for all resources (con-{env}-{region})"
  value       = local.name_prefix
}
