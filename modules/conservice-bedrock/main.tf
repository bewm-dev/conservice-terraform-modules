# -----------------------------------------------------------------------------
# conservice-bedrock
#
# Provisions Bedrock access, guardrails, invocation logging, and EKS Pod
# Identity for AI workloads. Designed to be called once per app that needs
# foundation model access.
#
# What this module creates:
#   - IAM policy for Bedrock model invocation (always)
#   - IAM role + EKS Pod Identity association (when cluster_name is set)
#   - Bedrock Guardrail (when enable_guardrails = true)
#   - Model invocation logging to S3/CloudWatch (when enable_invocation_logging = true)
#
# Naming:
#   IAM role:     {resource_prefix}-{env}-{region_code}-ai-{app_name}-bedrock-role
#   IAM policy:   {resource_prefix}-{env}-{region_code}-ai-{app_name}-bedrock-policy
#   Guardrail:    {resource_prefix}-{env}-{app_name}
#   Log group:    /aws/bedrock/{env}/{app_name}/invocations
# -----------------------------------------------------------------------------

locals {
  region_codes = {
    "us-east-1" = "use1"
    "us-east-2" = "use2"
    "us-west-1" = "usw1"
    "us-west-2" = "usw2"
  }
  region_code = local.region_codes[var.region]
  name_prefix = "${var.resource_prefix}-${var.env}-${local.region_code}-ai-${var.app_name}"

  create_pod_identity = var.cluster_name != "" && var.namespace != "" && var.service_account != ""

  ai_tags = merge(var.tags, {
    AIModel     = var.ai_model
    AIUseCase   = var.ai_use_case
    AICostGroup = var.ai_cost_group != "" ? var.ai_cost_group : var.app_name
    AppName     = var.app_name
    ManagedBy   = "terraform"
  })

  # Build model ARNs for IAM policy
  model_arns = [
    for model_id in var.model_ids :
    "arn:aws:bedrock:${var.region}::foundation-model/${model_id}"
  ]

  # Inference profile ARNs (cross-region inference)
  inference_profile_arns = [
    for model_id in var.model_ids :
    "arn:aws:bedrock:${var.region}:${var.aws_account_id}:inference-profile/*"
  ]

  # Guardrail defaults
  guardrail_defaults = {
    blocked_input_messaging  = "Your request was blocked by content safety policy."
    blocked_output_messaging = "The response was blocked by content safety policy."
    pii_action               = "ANONYMIZE"
    pii_types                = ["EMAIL", "PHONE", "US_SOCIAL_SECURITY_NUMBER", "CREDIT_DEBIT_CARD_NUMBER"]
    content_filters          = []
  }
  guardrail = merge(local.guardrail_defaults, var.guardrail_config)
}

# -----------------------------------------------------------------------------
# IAM Policy — Bedrock Model Invocation
#
# Grants InvokeModel + InvokeModelWithResponseStream on specified models.
# Optionally includes ApplyGuardrail and Knowledge Base permissions.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = concat(local.model_arns, local.inference_profile_arns)
  }

  dynamic "statement" {
    for_each = var.enable_guardrails ? [1] : []
    content {
      sid    = "BedrockGuardrails"
      effect = "Allow"
      actions = [
        "bedrock:ApplyGuardrail",
      ]
      resources = ["arn:aws:bedrock:${var.region}:${var.aws_account_id}:guardrail/*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_knowledge_bases ? [1] : []
    content {
      sid    = "BedrockKnowledgeBases"
      effect = "Allow"
      actions = [
        "bedrock:Retrieve",
        "bedrock:RetrieveAndGenerate",
      ]
      resources = length(var.knowledge_base_ids) > 0 ? [
        for kb_id in var.knowledge_base_ids :
        "arn:aws:bedrock:${var.region}:${var.aws_account_id}:knowledge-base/${kb_id}"
      ] : ["arn:aws:bedrock:${var.region}:${var.aws_account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_policy" "bedrock_invoke" {
  name   = "${local.name_prefix}-bedrock-policy"
  path   = "/ai/"
  policy = data.aws_iam_policy_document.bedrock_invoke.json

  tags = merge(local.ai_tags, {
    Name = "${local.name_prefix}-bedrock-policy"
  })
}

# -----------------------------------------------------------------------------
# IAM Role — EKS Pod Identity for Bedrock
#
# Created only when cluster_name, namespace, and service_account are provided.
# Trust policy allows EKS Pod Identity (pods.eks.amazonaws.com) to assume.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "pod_identity_trust" {
  count = local.create_pod_identity ? 1 : 0

  statement {
    sid     = "EKSPodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bedrock" {
  count = local.create_pod_identity ? 1 : 0

  name               = "${local.name_prefix}-bedrock-role"
  path               = "/ai/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust[0].json

  tags = merge(local.ai_tags, {
    Name = "${local.name_prefix}-bedrock-role"
  })
}

resource "aws_iam_role_policy_attachment" "bedrock" {
  count = local.create_pod_identity ? 1 : 0

  role       = aws_iam_role.bedrock[0].name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

resource "aws_eks_pod_identity_association" "bedrock" {
  count = local.create_pod_identity ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.bedrock[0].arn

  tags = merge(local.ai_tags, {
    Name = "${local.name_prefix}-pod-identity"
  })
}

# -----------------------------------------------------------------------------
# Bedrock Guardrail
#
# Created only when enable_guardrails = true.
# Configures PII detection/anonymization and optional content filters.
# -----------------------------------------------------------------------------

resource "aws_bedrock_guardrail" "app" {
  count = var.enable_guardrails ? 1 : 0

  name                      = "${var.resource_prefix}-${var.env}-${var.app_name}"
  description               = "Content safety guardrail for ${var.app_name} (${var.env})"
  blocked_input_messaging   = local.guardrail.blocked_input_messaging
  blocked_outputs_messaging = local.guardrail.blocked_output_messaging

  # PII detection and anonymization
  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = local.guardrail.pii_types
      content {
        type   = pii_entities_config.value
        action = local.guardrail.pii_action
      }
    }
  }

  # Content filters (hate, violence, etc.) — only if configured
  dynamic "content_policy_config" {
    for_each = length(local.guardrail.content_filters) > 0 ? [1] : []
    content {
      dynamic "filters_config" {
        for_each = local.guardrail.content_filters
        content {
          type            = filters_config.value.type
          input_strength  = lookup(filters_config.value, "input_strength", "MEDIUM")
          output_strength = lookup(filters_config.value, "output_strength", "MEDIUM")
        }
      }
    }
  }

  tags = merge(local.ai_tags, {
    Name = "${var.resource_prefix}-${var.env}-${var.app_name}-guardrail"
  })
}

# -----------------------------------------------------------------------------
# Model Invocation Logging
#
# Created only when enable_invocation_logging = true.
# Ships logs to S3 (required) and optionally CloudWatch.
# Logging is account-wide — only create ONE instance per account/region.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "bedrock" {
  count = var.enable_invocation_logging && var.enable_cloudwatch_logging ? 1 : 0

  name              = "/aws/bedrock/${var.env}/${var.app_name}/invocations"
  retention_in_days = var.log_retention_days

  tags = merge(local.ai_tags, {
    Name = "/aws/bedrock/${var.env}/${var.app_name}/invocations"
  })
}

# IAM role for Bedrock to write to CloudWatch
data "aws_iam_policy_document" "bedrock_logging_trust" {
  count = var.enable_invocation_logging && var.enable_cloudwatch_logging ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

data "aws_iam_policy_document" "bedrock_logging" {
  count = var.enable_invocation_logging && var.enable_cloudwatch_logging ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.bedrock[0].arn}:*"]
  }
}

resource "aws_iam_role" "bedrock_logging" {
  count = var.enable_invocation_logging && var.enable_cloudwatch_logging ? 1 : 0

  name               = "${local.name_prefix}-bedrock-logging-role"
  path               = "/ai/"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_trust[0].json

  tags = merge(local.ai_tags, {
    Name = "${local.name_prefix}-bedrock-logging-role"
  })
}

resource "aws_iam_role_policy" "bedrock_logging" {
  count = var.enable_invocation_logging && var.enable_cloudwatch_logging ? 1 : 0

  name   = "bedrock-cloudwatch-logging"
  role   = aws_iam_role.bedrock_logging[0].id
  policy = data.aws_iam_policy_document.bedrock_logging[0].json
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.enable_invocation_logging ? 1 : 0

  logging_config {
    embedding_data_delivery_enabled = true
    image_data_delivery_enabled     = true
    text_data_delivery_enabled      = true

    s3_config {
      bucket_name = replace(var.logging_s3_bucket_arn, "arn:aws:s3:::", "")
      key_prefix  = var.logging_s3_key_prefix
    }

    dynamic "cloudwatch_config" {
      for_each = var.enable_cloudwatch_logging ? [1] : []
      content {
        log_group_name = aws_cloudwatch_log_group.bedrock[0].name
        role_arn       = aws_iam_role.bedrock_logging[0].arn
      }
    }
  }
}
