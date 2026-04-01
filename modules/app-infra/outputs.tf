output "database_names" {
  description = "Map of database name to created database details"
  value       = { for k, v in module.databases : k => v.database_name }
}

output "bucket_arns" {
  description = "Map of bucket key to S3 bucket ARN"
  value       = { for k, v in aws_s3_bucket.buckets : k => v.arn }
}

output "bucket_names" {
  description = "Map of bucket key to S3 bucket name"
  value       = { for k, v in aws_s3_bucket.buckets : k => v.id }
}

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

output "topic_arns" {
  description = "Map of topic key to SNS topic ARN"
  value       = { for k, v in aws_sns_topic.topics : k => v.arn }
}
