# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "pod_identity_role_arn" {
  description = "IAM role ARN for Bedrock access via EKS Pod Identity"
  value       = length(aws_iam_role.bedrock) > 0 ? aws_iam_role.bedrock[0].arn : ""
}

output "pod_identity_role_name" {
  description = "IAM role name for Bedrock access"
  value       = length(aws_iam_role.bedrock) > 0 ? aws_iam_role.bedrock[0].name : ""
}

output "bedrock_policy_arn" {
  description = "IAM policy ARN for Bedrock model invocation"
  value       = aws_iam_policy.bedrock_invoke.arn
}

# -----------------------------------------------------------------------------
# Guardrails
# -----------------------------------------------------------------------------

output "guardrail_id" {
  description = "Bedrock Guardrail ID (pass to InvokeModel API)"
  value       = length(aws_bedrock_guardrail.app) > 0 ? aws_bedrock_guardrail.app[0].guardrail_id : ""
}

output "guardrail_arn" {
  description = "Bedrock Guardrail ARN"
  value       = length(aws_bedrock_guardrail.app) > 0 ? aws_bedrock_guardrail.app[0].guardrail_arn : ""
}

output "guardrail_version" {
  description = "Bedrock Guardrail version"
  value       = length(aws_bedrock_guardrail.app) > 0 ? aws_bedrock_guardrail.app[0].version : ""
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

output "log_group_name" {
  description = "CloudWatch log group for model invocation logs"
  value       = length(aws_cloudwatch_log_group.bedrock) > 0 ? aws_cloudwatch_log_group.bedrock[0].name : ""
}

# -----------------------------------------------------------------------------
# Tags (for downstream consumption)
# -----------------------------------------------------------------------------

output "ai_tags" {
  description = "AI-specific tags map — attach to related resources outside this module"
  value       = local.ai_tags
}
