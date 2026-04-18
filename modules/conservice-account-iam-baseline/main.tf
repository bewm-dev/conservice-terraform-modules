# -----------------------------------------------------------------------------
# Conservice Account Base Module
#
# Per-account baseline IAM roles and policies for the Conservice platform.
# Creates TF execution, EKS cluster, EKS node, and optional ECR pull and
# Aurora access roles.
#
# Naming: csvc-{env}-{resource}-{type}
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.resource_prefix}-${var.env}"
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

  # CI/CD role trust — allows GitHub Actions OIDC role (or similar) to assume
  # the TF execution role directly for automated infrastructure deployments.
  dynamic "statement" {
    for_each = length(var.ci_trusted_arns) > 0 ? [1] : []

    content {
      actions = ["sts:AssumeRole", "sts:TagSession"]

      principals {
        type        = "AWS"
        identifiers = var.ci_trusted_arns
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
  # ---------------------------------------------------------------------------
  # Allow: Infrastructure services (broad — deny fence limits the dangerous bits)
  # ---------------------------------------------------------------------------
  statement {
    sid = "IaCServices"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "s3:*",
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
      "events:*",
      "dynamodb:*",
      "states:*",
      "application-autoscaling:*",
    ]
    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # Allow: IAM role/policy management — scoped to known paths only
  # ---------------------------------------------------------------------------
  statement {
    sid = "IAMRoleManagement"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = flatten([
      for path in var.iam_allowed_paths : [
        "arn:aws:iam::${var.aws_account_id}:role${path}*",
        "arn:aws:iam::${var.aws_account_id}:policy${path}*",
        "arn:aws:iam::${var.aws_account_id}:instance-profile${path}*",
      ]
    ])
  }

  # ---------------------------------------------------------------------------
  # Allow: AttachRolePolicy/DetachRolePolicy — restricted to safe policies
  # (security audit H2). Without this, the TF execution role could attach
  # AdministratorAccess to any role in the allowed paths.
  # ---------------------------------------------------------------------------
  statement {
    sid = "IAMAttachPolicy"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = flatten([
      for path in var.iam_allowed_paths : [
        "arn:aws:iam::${var.aws_account_id}:role${path}*",
      ]
    ])

    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = concat(
        # Account-local policies in allowed paths
        [for path in var.iam_allowed_paths :
          "arn:aws:iam::${var.aws_account_id}:policy${path}*"
        ],
        # Account-local policies in root path (EKS community module creates these)
        ["arn:aws:iam::${var.aws_account_id}:policy/*"],
        # AWS managed policies used by EKS, nodes, and platform components
        var.allowed_managed_policy_arns,
      )
    }
  }

  # ---------------------------------------------------------------------------
  # Allow: IAM policy management (policies can exist without path prefix)
  # ---------------------------------------------------------------------------
  statement {
    sid = "IAMPolicyManagement"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      for path in var.iam_allowed_paths :
      "arn:aws:iam::${var.aws_account_id}:policy${path}*"
    ]
  }

  # ---------------------------------------------------------------------------
  # Allow: IAM read-only (needed for plan, discovery, data sources)
  # ---------------------------------------------------------------------------
  statement {
    sid = "IAMReadOnly"
    actions = [
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListInstanceProfiles",
      "iam:ListOpenIDConnectProviders",
      "iam:GetOpenIDConnectProvider",
      "iam:ListSAMLProviders",
      "iam:GetAccountSummary",
      "iam:GetAccountAuthorizationDetails",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
    ]
    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # Allow: OIDC provider management (for EKS Pod Identity / IRSA)
  # ---------------------------------------------------------------------------
  statement {
    sid = "IAMOIDCProviders"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:oidc-provider/*"]
  }

  # ---------------------------------------------------------------------------
  # Allow: Service-linked roles (only for known AWS services)
  # ---------------------------------------------------------------------------
  statement {
    sid = "IAMServiceLinkedRoles"
    actions = [
      "iam:CreateServiceLinkedRole",
      "iam:DeleteServiceLinkedRole",
      "iam:GetServiceLinkedRoleDeletionStatus",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/aws-service-role/*"]
  }

  # ---------------------------------------------------------------------------
  # Allow: Cross-account assume into platform account
  # Needed for app Terraform to create ECR repos via the aws.ecr provider.
  # Scoped to /infrastructure/ roles in the platform account only.
  # ---------------------------------------------------------------------------
  dynamic "statement" {
    for_each = var.platform_account_id != null ? [1] : []
    content {
      sid       = "CrossAccountAssume"
      actions   = ["sts:AssumeRole"]
      resources = compact([
        "arn:aws:iam::${var.platform_account_id}:role/infrastructure/*",
        var.org_account_id != null ? "arn:aws:iam::${var.org_account_id}:role/sso/*" : "",
      ])
    }
  }

  # ---------------------------------------------------------------------------
  # Allow: Pull platform/forge-render and other platform-owned images from
  # platform ECR. The forge.yaml → HCL render step in every scaffolded app's
  # terraform workflow runs `docker run <platform-ecr>/platform/forge-render`
  # BEFORE `terraform init`, so the tf-execution-role itself (not just the
  # ecr_pull role for pods) needs GetAuthorizationToken + pull permissions.
  # Resource-based policy on platform ECR scopes which repos are readable;
  # here we grant the API actions. GetAuthorizationToken is a global action
  # and must be Resource="*".
  # ---------------------------------------------------------------------------
  statement {
    sid       = "ECRAuthForRenderPull"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPullPlatformImages"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = var.platform_account_id != null ? [
      "arn:aws:ecr:*:${var.platform_account_id}:repository/platform/*",
    ] : []
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
# TF Execution — Deny Fence
#
# Explicit deny on actions the TF execution role should NEVER perform,
# regardless of what Terraform code defines. This is the security boundary.
#
# Pattern: broad allows + deny fence is more maintainable than trying to
# whitelist every action. Adding new resource types "just works" without
# IAM updates. The deny fence is stable and rarely changes.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "tf_deny_fence" {
  # ---------------------------------------------------------------------------
  # Deny: IAM user creation — roles only, no long-lived credentials
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyIAMUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateVirtualMFADevice",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:AddUserToGroup",
      "iam:CreateGroup",
      "iam:AttachGroupPolicy",
      "iam:PutGroupPolicy",
    ]
    resources = ["*"]
  }

  # NOTE: IAM role/policy writes are implicitly denied outside allowed paths
  # because the Allow statements (IAMRoleManagement, IAMPolicyManagement)
  # only grant access to ARNs within var.iam_allowed_paths. No explicit
  # deny needed — implicit deny handles the rest.

  # ---------------------------------------------------------------------------
  # Deny: Organization and account management
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyOrgAndAccountManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # Deny: Deleting Terraform state buckets
  # Belt + suspenders with prevent_destroy in code.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyDeleteStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-tf-state-*",
    ]
  }

  # ---------------------------------------------------------------------------
  # Deny: EC2 RunInstances without ManagedBy tag
  # Prevents untagged orphan instances from CI.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyUntaggedEC2"
    effect = "Deny"
    actions = [
      "ec2:RunInstances",
    ]
    resources = ["arn:aws:ec2:*:${var.aws_account_id}:instance/*"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/ManagedBy"
      values   = ["true"]
    }
  }

  # ---------------------------------------------------------------------------
  # Deny: Disabling security services
  # Only the security account (via delegation) should manage these.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyDisableSecurity"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "securityhub:DisableSecurityHub",
      "access-analyzer:DeleteAnalyzer",
    ]
    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # Deny: KMS key deletion with dangerously short window
  # Minimum 14-day wait for key deletion.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyRapidKMSKeyDeletion"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
    ]
    resources = ["*"]

    condition {
      test     = "NumericLessThan"
      variable = "kms:ScheduleKeyDeletionPendingWindowInDays"
      values   = ["14"]
    }
  }
}

resource "aws_iam_policy" "tf_deny_fence" {
  name   = "${local.name_prefix}-tf-deny-fence-policy"
  path   = "/infrastructure/"
  policy = data.aws_iam_policy_document.tf_deny_fence.json
}

resource "aws_iam_role_policy_attachment" "tf_deny_fence" {
  role       = aws_iam_role.tf_execution.name
  policy_arn = aws_iam_policy.tf_deny_fence.arn
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
    resources = ["arn:aws:ecr:*:*:repository/${var.project}-*"]
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
      "arn:aws:s3:::${var.project}-${var.env}-aurora-*",
      "arn:aws:s3:::${var.project}-${var.env}-aurora-*/*",
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
