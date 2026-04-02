output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint for the Aurora cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Port for the Aurora cluster"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Name of the default database"
  value       = aws_rds_cluster.this.database_name
}

output "cluster_identifier" {
  description = "Identifier of the Aurora cluster"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "ARN of the Aurora cluster"
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "Resource ID of the Aurora cluster (for IAM auth policies)"
  value       = aws_rds_cluster.this.cluster_resource_id
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
  value       = aws_rds_cluster_instance.this[*].identifier
}

output "instance_endpoints" {
  description = "List of instance endpoints"
  value       = aws_rds_cluster_instance.this[*].endpoint
}

output "subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.this.name
}

output "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group"
  value       = aws_rds_cluster_parameter_group.this.name
}

output "instance_parameter_group_name" {
  description = "Name of the instance parameter group"
  value       = aws_db_parameter_group.this.name
}
