output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster"
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint for the Aurora cluster"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "port" {
  description = "Port for the Aurora cluster"
  value       = aws_rds_cluster.aurora.port
}

output "database_name" {
  description = "Name of the default database"
  value       = aws_rds_cluster.aurora.database_name
}

output "cluster_identifier" {
  description = "Identifier of the Aurora cluster"
  value       = aws_rds_cluster.aurora.cluster_identifier
}

output "cluster_arn" {
  description = "ARN of the Aurora cluster"
  value       = aws_rds_cluster.aurora.arn
}

output "cluster_resource_id" {
  description = "Resource ID of the Aurora cluster (for IAM auth policies)"
  value       = aws_rds_cluster.aurora.cluster_resource_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for Aurora encryption"
  value       = aws_kms_key.aurora.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for Aurora encryption"
  value       = aws_kms_key.aurora.key_id
}

output "instance_identifiers" {
  description = "List of instance identifiers"
  value       = aws_rds_cluster_instance.aurora[*].identifier
}

output "instance_endpoints" {
  description = "List of instance endpoints"
  value       = aws_rds_cluster_instance.aurora[*].endpoint
}

output "subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.aurora.name
}

output "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group"
  value       = aws_rds_cluster_parameter_group.aurora.name
}

output "instance_parameter_group_name" {
  description = "Name of the instance parameter group"
  value       = aws_db_parameter_group.aurora.name
}
