# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------

output "bucket_arns" {
  description = "Map of bucket key to S3 bucket ARN"
  value       = { for k, v in module.s3_buckets : k => v.s3_bucket_arn }
}

output "bucket_names" {
  description = "Map of bucket key to S3 bucket name"
  value       = { for k, v in module.s3_buckets : k => v.s3_bucket_id }
}

# -----------------------------------------------------------------------------
# SQS
# -----------------------------------------------------------------------------

output "queue_arns" {
  description = "Map of queue key to SQS queue ARN"
  value       = { for k, v in aws_sqs_queue.queues : k => v.arn }
}

output "queue_urls" {
  description = "Map of queue key to SQS queue URL"
  value       = { for k, v in aws_sqs_queue.queues : k => v.url }
}

output "dlq_arns" {
  description = "Map of DLQ key to SQS DLQ ARN"
  value       = { for k, v in aws_sqs_queue.dlqs : k => v.arn }
}

# -----------------------------------------------------------------------------
# SNS
# -----------------------------------------------------------------------------

output "topic_arns" {
  description = "Map of topic key to SNS topic ARN"
  value       = { for k, v in aws_sns_topic.topics : k => v.arn }
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

output "secret_arns" {
  description = "Map of secret key to Secrets Manager ARN"
  value       = { for k, v in aws_secretsmanager_secret.secrets : k => v.arn }
}

output "secret_names" {
  description = "Map of secret key to Secrets Manager name"
  value       = { for k, v in aws_secretsmanager_secret.secrets : k => v.name }
}

# -----------------------------------------------------------------------------
# Databases
# -----------------------------------------------------------------------------

output "database_names" {
  description = "Map of database key to created database name"
  value       = { for k, v in module.databases : k => v.database_name }
}

output "database_service_roles" {
  description = "Map of database key to service role name (for IAM rds-db:connect policies)"
  value       = { for k, v in module.databases : k => v.service_role_name }
}

output "database_all_iam_roles" {
  description = "Map of database key to all IAM role names"
  value       = { for k, v in module.databases : k => v.all_iam_role_names }
}

# -----------------------------------------------------------------------------
# Pod Identity
# -----------------------------------------------------------------------------

output "pod_identity_role_arn" {
  description = "IAM role ARN for the app's Pod Identity"
  value       = length(aws_iam_role.pod_identity) > 0 ? aws_iam_role.pod_identity[0].arn : ""
}

output "ci_role_arn" {
  description = "IAM role ARN for app CI (GitHub Actions assumes this for plan/apply/push)"
  value       = length(aws_iam_role.ci) > 0 ? aws_iam_role.ci[0].arn : ""
}
