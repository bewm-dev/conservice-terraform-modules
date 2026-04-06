# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# -----------------------------------------------------------------------------

output "lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller"
  value       = var.enable_lbc ? aws_iam_role.lbc[0].arn : null
}

# -----------------------------------------------------------------------------
# External DNS
# -----------------------------------------------------------------------------

output "external_dns_role_arn" {
  description = "IAM role ARN for External DNS"
  value       = var.enable_external_dns ? aws_iam_role.external_dns[0].arn : null
}

# -----------------------------------------------------------------------------
# External Secrets Operator
# -----------------------------------------------------------------------------

output "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = var.enable_eso ? aws_iam_role.eso[0].arn : null
}

# -----------------------------------------------------------------------------
# Karpenter
# -----------------------------------------------------------------------------

output "karpenter_role_arn" {
  description = "IAM role ARN for Karpenter"
  value       = var.enable_karpenter ? aws_iam_role.karpenter[0].arn : null
}

output "karpenter_queue_name" {
  description = "Name of the Karpenter interruption SQS queue"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter_interruption[0].name : null
}

output "karpenter_queue_arn" {
  description = "ARN of the Karpenter interruption SQS queue"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter_interruption[0].arn : null
}
