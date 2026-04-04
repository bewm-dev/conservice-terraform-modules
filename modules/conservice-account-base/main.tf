# -----------------------------------------------------------------------------
# Conservice Account Base Module
#
# Per-account baseline IAM roles and policies for the Conservice platform.
# Creates TF execution, EKS cluster, EKS node, and optional ECR pull and
# Aurora access roles.
#
# Naming: con-{env}-{resource}-{type}
# -----------------------------------------------------------------------------

locals {
  name_prefix = "con-${var.env}"
}

# -----------------------------------------------------------------------------
# TF Execution Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "tf_execution_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.role_type == "cross-account" ? "arn:aws:iam::${var.platform_account_id}:root" : "arn:aws:iam::${var.aws_account_id}:root"]
    }

    dynamic "condition" {
      for_each = var.role_type == "cross-account" ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.aws_account_id]
      }
    }

    dynamic "condition" {
      for_each = var.role_type == "self-contained" ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:PrincipalTag/Role"
        values   = ["ci-terraform"]
      }
    }
  }
}

resource "aws_iam_role" "tf_execution" {
  name               = "${local.name_prefix}-tf-execution-role"
  path               = "/infrastructure/"
  assume_role_policy = data.aws_iam_policy_document.tf_execution_trust.json
}

# -----------------------------------------------------------------------------
# TF Execution Policy
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "tf_execution" {
  statement {
    sid = "IaCServices"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "s3:*",
      "iam:*",
      "kms:*",
      "secretsmanager:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "cloudwatch:*",
      "logs:*",
      "route53:*",
      "acm:*",
      "sqs:*",
      "sns:*",
      "ssm:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "StateBucketAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::conservice-tf-state-${var.env}",
      "arn:aws:s3:::conservice-tf-state-${var.env}/*",
    ]
  }

}

resource "aws_iam_policy" "tf_execution" {
  name   = "${local.name_prefix}-tf-execution-policy"
  path   = "/infrastructure/"
  policy = data.aws_iam_policy_document.tf_execution.json
}

resource "aws_iam_role_policy_attachment" "tf_execution" {
  role       = aws_iam_role.tf_execution.name
  policy_arn = aws_iam_policy.tf_execution.arn
}

# -----------------------------------------------------------------------------
# EKS Cluster Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# -----------------------------------------------------------------------------
# EKS Node Role + Instance Profile
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_node_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name_prefix}-eks-node-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.eks_node_trust.json
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "eks_node" {
  name = "${local.name_prefix}-eks-node-profile"
  path = "/eks/"
  role = aws_iam_role.eks_node.name
}

# -----------------------------------------------------------------------------
# ECR Cross-Account Pull Role (conditional)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_pull_trust" {
  count = var.enable_ecr_pull_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }
  }
}

resource "aws_iam_role" "ecr_pull" {
  count = var.enable_ecr_pull_role ? 1 : 0

  name               = "${local.name_prefix}-ecr-cross-account-pull-role"
  path               = "/ecr/"
  assume_role_policy = data.aws_iam_policy_document.ecr_pull_trust[0].json
}

data "aws_iam_policy_document" "ecr_pull" {
  count = var.enable_ecr_pull_role ? 1 : 0

  statement {
    sid = "ECRPullAccess"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = ["arn:aws:ecr:*:*:repository/conservice-*"]
  }

  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr_pull" {
  count = var.enable_ecr_pull_role ? 1 : 0

  name   = "${local.name_prefix}-ecr-cross-account-pull-policy"
  path   = "/ecr/"
  policy = data.aws_iam_policy_document.ecr_pull[0].json
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  count = var.enable_ecr_pull_role ? 1 : 0

  role       = aws_iam_role.ecr_pull[0].name
  policy_arn = aws_iam_policy.ecr_pull[0].arn
}

# -----------------------------------------------------------------------------
# Aurora Access Role (conditional)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "aurora_trust" {
  count = var.enable_aurora_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aurora" {
  count = var.enable_aurora_role ? 1 : 0

  name               = "${local.name_prefix}-aurora-access-role"
  path               = "/database/"
  assume_role_policy = data.aws_iam_policy_document.aurora_trust[0].json
}

data "aws_iam_policy_document" "aurora" {
  count = var.enable_aurora_role ? 1 : 0

  statement {
    sid = "S3Access"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::conservice-${var.env}-aurora-*",
      "arn:aws:s3:::conservice-${var.env}-aurora-*/*",
    ]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:${var.aws_account_id}:*"]
  }
}

resource "aws_iam_policy" "aurora" {
  count = var.enable_aurora_role ? 1 : 0

  name   = "${local.name_prefix}-aurora-access-policy"
  path   = "/database/"
  policy = data.aws_iam_policy_document.aurora[0].json
}

resource "aws_iam_role_policy_attachment" "aurora" {
  count = var.enable_aurora_role ? 1 : 0

  role       = aws_iam_role.aurora[0].name
  policy_arn = aws_iam_policy.aurora[0].arn
}
