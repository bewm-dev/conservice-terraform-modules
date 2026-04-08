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
# CloudWatch Container Insights
# -----------------------------------------------------------------------------

output "container_insights_role_arn" {
  description = "IAM role ARN for CloudWatch Container Insights"
  value       = var.enable_container_insights ? aws_iam_role.container_insights[0].arn : null
}

# -----------------------------------------------------------------------------
# Kargo
# -----------------------------------------------------------------------------

output "kargo_role_arn" {
  description = "IAM role ARN for Kargo ECR image discovery"
  value       = var.enable_kargo ? aws_iam_role.kargo[0].arn : null
}
