# -----------------------------------------------------------------------------
# VPC Passthrough
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "List of private app subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "List of private database subnet IDs"
  value       = module.vpc.private_db_subnet_ids
}

output "private_app_route_table_ids" {
  description = "Map of AZ to private app route table ID"
  value       = module.vpc.private_app_route_table_ids
}

output "private_db_route_table_ids" {
  description = "Map of AZ to private database route table ID"
  value       = module.vpc.private_db_route_table_ids
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group for Aurora/RDS"
  value       = module.vpc.db_subnet_group_name
}

output "nat_public_ips" {
  description = "Map of AZ to NAT Gateway public IP"
  value       = module.vpc.nat_public_ips
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

output "eks_cluster_additional_sg_id" {
  description = "ID of the EKS cluster additional security group (empty string if disabled)"
  value       = var.create_eks_sg ? aws_security_group.eks_cluster_additional[0].id : ""
}

output "aurora_sg_id" {
  description = "ID of the Aurora security group (empty string if disabled)"
  value       = var.create_aurora_sg ? aws_security_group.aurora[0].id : ""
}

output "internal_sg_id" {
  description = "ID of the internal security group"
  value       = aws_security_group.internal.id
}

# -----------------------------------------------------------------------------
# Transit Gateway
# -----------------------------------------------------------------------------

output "tgw_attachment_id" {
  description = "ID of the Transit Gateway VPC attachment (empty string if no TGW)"
  value       = var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : ""
}
