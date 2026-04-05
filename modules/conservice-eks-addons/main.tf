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

  # EC2 + ELB describe permissions
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:DescribeCoipPools",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeInstanceTypes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
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

  # EC2 security group creation (scoped by request tag)
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = [var.cluster_name]
    }
  }

  # EC2 security group modification (scoped by resource tag)
  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [var.cluster_name]
    }
  }

  # ELB create with tag condition
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = [var.cluster_name]
    }
  }

  # ELB tagging scoped to specific resource types
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
  }

  # ELB modify and delete actions (scoped by resource tag)
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
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [var.cluster_name]
    }
  }

  # ELB target registration scoped to target groups
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"]
  }

  # ELB listener/rule management (scoped to LBC-managed resources)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [var.cluster_name]
    }
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
}

# =============================================================================
# Karpenter
# =============================================================================

# -----------------------------------------------------------------------------
# Karpenter — IAM
# -----------------------------------------------------------------------------

resource "aws_iam_role" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name               = "${var.cluster_name}-karpenter-role"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = { Name = "${var.cluster_name}-karpenter-role" }
}

resource "aws_iam_policy" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name   = "${var.cluster_name}-karpenter-policy"
  path   = "/eks/"
  policy = data.aws_iam_policy_document.karpenter[0].json
  tags   = { Name = "${var.cluster_name}-karpenter-policy" }
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter[0].name
  policy_arn = aws_iam_policy.karpenter[0].arn
}

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter[0].arn
}

data "aws_iam_policy_document" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  # EC2 read-only (no resource-level scoping needed)
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSpotPriceHistory",
    ]
    resources = ["*"]
  }

  # EC2 provisioning — create with Karpenter tag condition
  statement {
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # EC2 termination — scoped to Karpenter-managed resources
  statement {
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # PassRole to node role
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.node_role_arn]
  }

  # EKS cluster describe
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:*:${var.aws_account_id}:cluster/${var.cluster_name}"]
  }

  # SSM for EKS optimized AMI lookup
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*::parameter/aws/service/eks/optimized-ami/*"]
  }

  # Pricing API
  statement {
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # SQS for interruption handling
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.karpenter_interruption[0].arn]
  }
}

# -----------------------------------------------------------------------------
# Karpenter — SQS Interruption Queue
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "karpenter_interruption" {
  count = var.enable_karpenter ? 1 : 0

  name                      = "${var.cluster_name}-karpenter-interruption-queue"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${var.cluster_name}-karpenter-interruption-queue" }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  count = var.enable_karpenter ? 1 : 0

  queue_url = aws_sqs_queue.karpenter_interruption[0].id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue[0].json
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  count = var.enable_karpenter ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption[0].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# Karpenter — EventBridge Rules
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.cluster_name}-spot-interruption-rule"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = { Name = "${var.cluster_name}-spot-interruption-rule" }
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  count = var.enable_karpenter ? 1 : 0

  rule = aws_cloudwatch_event_rule.spot_interruption[0].name
  arn  = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "instance_rebalance" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.cluster_name}-instance-rebalance-rule"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = { Name = "${var.cluster_name}-instance-rebalance-rule" }
}

resource "aws_cloudwatch_event_target" "instance_rebalance" {
  count = var.enable_karpenter ? 1 : 0

  rule = aws_cloudwatch_event_rule.instance_rebalance[0].name
  arn  = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.cluster_name}-instance-state-change-rule"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
  tags = { Name = "${var.cluster_name}-instance-state-change-rule" }
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  count = var.enable_karpenter ? 1 : 0

  rule = aws_cloudwatch_event_rule.instance_state_change[0].name
  arn  = aws_sqs_queue.karpenter_interruption[0].arn
}

# =============================================================================
# CloudWatch Container Insights (OTEL-based)
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

data "aws_eks_addon_version" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = data.aws_eks_cluster.this[0].version
  most_recent        = true
}

data "aws_eks_cluster" "this" {
  count = var.enable_container_insights ? 1 : 0
  name  = var.cluster_name
}

resource "aws_eks_addon" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name  = var.cluster_name
  addon_name    = "amazon-cloudwatch-observability"
  addon_version = data.aws_eks_addon_version.container_insights[0].version

  tags = { Name = "${var.cluster_name}-container-insights" }
}
