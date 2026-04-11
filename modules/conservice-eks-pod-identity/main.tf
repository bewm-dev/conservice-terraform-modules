# -----------------------------------------------------------------------------
# Shared — Pod Identity Trust Policy
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# =============================================================================
# AWS Load Balancer Controller
# =============================================================================

resource "aws_iam_role" "lbc" {
  count = var.enable_lbc ? 1 : 0

  name               = "${var.cluster_name}-lbc-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = { Name = "${var.cluster_name}-lbc-role" }
}

resource "aws_iam_policy" "lbc" {
  count = var.enable_lbc ? 1 : 0

  name   = "${var.cluster_name}-lbc-policy"
  path   = "/eks/"
  policy = data.aws_iam_policy_document.lbc[0].json
  tags   = { Name = "${var.cluster_name}-lbc-policy" }
}

resource "aws_iam_role_policy_attachment" "lbc" {
  count = var.enable_lbc ? 1 : 0

  role       = aws_iam_role.lbc[0].name
  policy_arn = aws_iam_policy.lbc[0].arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  count = var.enable_lbc ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc[0].arn
}

data "aws_iam_policy_document" "lbc" {
  count = var.enable_lbc ? 1 : 0

  # Service-linked role creation
  statement {
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  # Read-only: EC2 + ELB discovery
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCoipPools",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeIpamPools",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeVpcs",
      "ec2:GetCoipPoolUsage",
      "ec2:GetSecurityGroupsForVpc",
      "elasticloadbalancing:DescribeCapacityReservation",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
    ]
    resources = ["*"]
  }

  # Cognito, ACM, IAM certs, WAF, Shield
  statement {
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }

  # EC2 security group — create + ingress/egress rules
  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
    ]
    resources = ["*"]
  }

  # EC2 tags on SG at creation (must have elbv2 cluster tag)
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:*:security-group/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # EC2 tags on existing SGs (must already have elbv2 cluster tag)
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # EC2 SG delete (scoped by resource tag)
  statement {
    effect    = "Allow"
    actions   = ["ec2:DeleteSecurityGroup"]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB create (must tag with elbv2 cluster tag)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB listener/rule create+delete (no tag condition — these inherit from LB)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
    ]
    resources = ["*"]
  }

  # ELB tags on LB/TG at creation
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values   = ["CreateTargetGroup", "CreateLoadBalancer"]
    }

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB tags on existing LB/TG (must already have elbv2 tag)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB tags on listeners/rules (no tag condition — inherits from LB)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
    ]
  }

  # ELB modify/delete (scoped by resource tag)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:ModifyCapacityReservation",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  # ELB target registration
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"]
  }

  # ELB listener/rule modification + WAF
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetRulePriorities",
    ]
    resources = ["*"]
  }
}

# =============================================================================
# External DNS
# =============================================================================

resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name               = "${var.cluster_name}-external-dns-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = { Name = "${var.cluster_name}-external-dns-role" }
}

resource "aws_iam_policy" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name   = "${var.cluster_name}-external-dns-policy"
  path   = "/eks/"
  policy = data.aws_iam_policy_document.external_dns[0].json
  tags   = { Name = "${var.cluster_name}-external-dns-policy" }
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

resource "aws_eks_pod_identity_association" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
}

# Same role, second service account for private zone ExternalDNS
resource "aws_eks_pod_identity_association" "external_dns_private" {
  count = var.enable_external_dns ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns-private"
  role_arn        = aws_iam_role.external_dns[0].arn
}

data "aws_iam_policy_document" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["route53:ChangeResourceRecordSets"]
    resources = length(var.route53_zone_ids) > 0 ? [
      for id in var.route53_zone_ids : "arn:aws:route53:::hostedzone/${id}"
    ] : ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.route53_cross_account_role_arn != "" ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["sts:AssumeRole", "sts:TagSession"]
      resources = [var.route53_cross_account_role_arn]
    }
  }
}

# =============================================================================
# External Secrets Operator
# =============================================================================

resource "aws_iam_role" "eso" {
  count = var.enable_eso ? 1 : 0

  name               = "${var.cluster_name}-eso-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = { Name = "${var.cluster_name}-eso-role" }
}

resource "aws_iam_policy" "eso" {
  count = var.enable_eso ? 1 : 0

  name   = "${var.cluster_name}-eso-policy"
  path   = "/eks/"
  policy = data.aws_iam_policy_document.eso[0].json
  tags   = { Name = "${var.cluster_name}-eso-policy" }
}

resource "aws_iam_role_policy_attachment" "eso" {
  count = var.enable_eso ? 1 : 0

  role       = aws_iam_role.eso[0].name
  policy_arn = aws_iam_policy.eso[0].arn
}

resource "aws_eks_pod_identity_association" "eso" {
  count = var.enable_eso ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso[0].arn
}

data "aws_iam_policy_document" "eso" {
  count = var.enable_eso ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
    ]
    resources = ["arn:aws:secretsmanager:*:${var.aws_account_id}:secret:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:aws:ssm:*:${var.aws_account_id}:parameter/*"]
  }

  # KMS decrypt — required when secrets are encrypted with customer-managed keys
  dynamic "statement" {
    for_each = length(var.secrets_kms_key_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = var.secrets_kms_key_arns
    }
  }
}

# =============================================================================
# CloudWatch Container Insights
# =============================================================================

resource "aws_iam_role" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  name               = "${var.cluster_name}-cloudwatch-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = { Name = "${var.cluster_name}-cloudwatch-role" }
}

resource "aws_iam_role_policy_attachment" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  role       = aws_iam_role.container_insights[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_pod_identity_association" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = aws_iam_role.container_insights[0].arn
}

# =============================================================================
# Kargo — ECR Image Discovery
# Kargo's Warehouse needs to list/describe tags in ECR repos to discover new
# images for promotion. Only needed on the mgmt cluster where Kargo runs.
# =============================================================================

resource "aws_iam_role" "kargo" {
  count = var.enable_kargo ? 1 : 0

  name               = "${var.cluster_name}-kargo-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = { Name = "${var.cluster_name}-kargo-role" }
}

resource "aws_iam_policy" "kargo" {
  count = var.enable_kargo ? 1 : 0

  name   = "${var.cluster_name}-kargo-policy"
  path   = "/eks/"
  policy = data.aws_iam_policy_document.kargo[0].json
  tags   = { Name = "${var.cluster_name}-kargo-policy" }
}

resource "aws_iam_role_policy_attachment" "kargo" {
  count = var.enable_kargo ? 1 : 0

  role       = aws_iam_role.kargo[0].name
  policy_arn = aws_iam_policy.kargo[0].arn
}

resource "aws_eks_pod_identity_association" "kargo" {
  count = var.enable_kargo ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "kargo"
  service_account = "kargo-controller"
  role_arn        = aws_iam_role.kargo[0].arn
}

data "aws_iam_policy_document" "kargo" {
  count = var.enable_kargo ? 1 : 0

  # ECR auth token — required for any ECR API access
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR read — list and inspect image tags across all repos
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = ["arn:aws:ecr:*:${var.aws_account_id}:repository/*"]
  }
}
