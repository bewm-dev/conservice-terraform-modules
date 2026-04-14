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
# EventBridge
# -----------------------------------------------------------------------------

output "event_bus_arns" {
  description = "Map of event bus key to EventBridge bus ARN"
  value       = { for k, v in aws_cloudwatch_event_bus.buses : k => v.arn }
}

output "event_bus_names" {
  description = "Map of event bus key to EventBridge bus name"
  value       = { for k, v in aws_cloudwatch_event_bus.buses : k => v.name }
}

# -----------------------------------------------------------------------------
# Step Functions
# -----------------------------------------------------------------------------

output "state_machine_arns" {
  description = "Map of state machine key to Step Functions ARN"
  value       = { for k, v in aws_sfn_state_machine.machines : k => v.arn }
}

output "state_machine_names" {
  description = "Map of state machine key to Step Functions name"
  value       = { for k, v in aws_sfn_state_machine.machines : k => v.name }
}

# -----------------------------------------------------------------------------
# DynamoDB
# -----------------------------------------------------------------------------

output "table_arns" {
  description = "Map of table key to DynamoDB table ARN"
  value       = { for k, v in aws_dynamodb_table.tables : k => v.arn }
}

output "table_names" {
  description = "Map of table key to DynamoDB table name"
  value       = { for k, v in aws_dynamodb_table.tables : k => v.name }
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

output "app_config_secret_arn" {
  description = "Secrets Manager ARN for {app}/config (manual values)"
  value       = length(aws_secretsmanager_secret.app_config) > 0 ? aws_secretsmanager_secret.app_config[0].arn : ""
}

output "app_config_secret_name" {
  description = "Secrets Manager name for {app}/config (manual values)"
  value       = length(aws_secretsmanager_secret.app_config) > 0 ? aws_secretsmanager_secret.app_config[0].name : ""
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

# ECR repos managed centrally — see platform/global/ecr outputs

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

# -----------------------------------------------------------------------------
# Temporal
# -----------------------------------------------------------------------------

output "temporal_namespace_id" {
  description = "Temporal Cloud namespace ID"
  value       = length(module.temporal) > 0 ? module.temporal[0].namespace_id : ""
}

output "temporal_namespace_name" {
  description = "Temporal Cloud namespace name"
  value       = length(module.temporal) > 0 ? module.temporal[0].namespace_name : ""
}

output "temporal_grpc_endpoint" {
  description = "gRPC endpoint for Temporal workers"
  value       = length(module.temporal) > 0 ? module.temporal[0].grpc_endpoint : ""
}

output "temporal_api_key_secret_arn" {
  description = "Secrets Manager ARN for the Temporal API key"
  value       = length(module.temporal) > 0 ? module.temporal[0].api_key_secret_arn : ""
}
