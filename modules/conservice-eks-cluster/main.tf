# -----------------------------------------------------------------------------
# KMS Key — EKS Secrets Encryption
# -----------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption - ${var.cluster_name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-key"
  })

}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source = "../aws-eks-cluster"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  subnet_ids      = var.subnet_ids

  cluster_role_arn              = var.cluster_role_arn
  node_role_arn                 = var.node_role_arn
  cluster_admin_arns            = var.cluster_admin_arns
  additional_security_group_ids = var.additional_security_group_ids
  kms_key_arn                   = aws_kms_key.eks.arn

  env  = var.env
  tags = var.tags
}
