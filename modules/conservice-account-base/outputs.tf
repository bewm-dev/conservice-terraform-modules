# -----------------------------------------------------------------------------
# Conservice Account Base — Outputs
# -----------------------------------------------------------------------------

output "tf_execution_role_arn" {
  description = "ARN of the Terraform execution IAM role"
  value       = aws_iam_role.tf_execution.arn
}

output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_instance_profile_name" {
  description = "Name of the EKS node instance profile"
  value       = aws_iam_instance_profile.eks_node.name
}

output "ecr_cross_account_pull_role_arn" {
  description = "ARN of the ECR cross-account pull role (empty string if disabled)"
  value       = var.enable_ecr_pull_role ? aws_iam_role.ecr_pull[0].arn : ""
}

output "aurora_access_role_arn" {
  description = "ARN of the Aurora access role (empty string if disabled)"
  value       = var.enable_aurora_role ? aws_iam_role.aurora[0].arn : ""
}
