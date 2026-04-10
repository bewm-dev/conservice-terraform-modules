# -----------------------------------------------------------------------------
# conservice-app-resources
#
# Provisions app-level AWS resources from a single infra.yaml file.
# Dev teams edit infra.yaml in their app repo; this module + CI handles the rest.
#
# Config merge (2 layers):
#   1. infra/infra.yaml         — all resource definitions (required)
#   2. infra/envs/<env>.yaml    — environment overrides (optional, merged on top)
#
# Naming:
#   S3 buckets:  {project}-{env}-{app_name}-{key}  (global namespace)
#   SQS queues:  {resource_prefix}-{env}-{region_code}-{app_name}-{key}-queue
#   SNS topics:  {resource_prefix}-{env}-{region_code}-{app_name}-{key}-topic
#   Secrets:     {project}-{env}-{app_name}-{key}
#   Databases:   key becomes the database name in shared Aurora
# -----------------------------------------------------------------------------

locals {
  # Region code lookup
  region_codes = {
    "us-east-1" = "use1"
    "us-east-2" = "use2"
    "us-west-1" = "usw1"
    "us-west-2" = "usw2"
  }
  region_code     = local.region_codes[var.region]
  name_prefix     = "${var.resource_prefix}-${var.env}-${local.region_code}-${var.app_name}"
  app_role_prefix = "${var.resource_prefix}-${var.env}-${local.region_code}-app-${var.app_name}"

  # ---------------------------------------------------------------------------
  # Config source: HCL variables (config_path = null) or YAML file
  # ---------------------------------------------------------------------------

  use_yaml = var.config_path != null

  config = local.use_yaml ? yamldecode(file("${var.config_path}/infra.yaml")) : {}

  env_override_path = local.use_yaml ? "${var.config_path}/envs/${var.env}.yaml" : ""
  has_env_override  = local.use_yaml && fileexists(local.env_override_path)
  env_override      = local.has_env_override ? yamldecode(file(local.env_override_path)) : {}

  # HCL vars take effect when config_path is null; YAML takes effect when set
  buckets      = local.use_yaml ? lookup(local.env_override, "buckets", lookup(local.config, "buckets", {})) : var.buckets
  queues       = local.use_yaml ? lookup(local.env_override, "queues", lookup(local.config, "queues", {})) : var.queues
  topics       = local.use_yaml ? lookup(local.env_override, "topics", lookup(local.config, "topics", {})) : var.topics
  databases    = local.use_yaml ? lookup(local.env_override, "databases", lookup(local.config, "databases", {})) : var.databases
  secrets      = local.use_yaml ? lookup(local.env_override, "secrets", lookup(local.config, "secrets", {})) : var.secrets
  pod_identity = local.use_yaml ? lookup(local.config, "pod_identity", null) : var.pod_identity
  ci_role      = local.use_yaml ? lookup(local.config, "ci_role", null) : var.ci_role
  temporal     = local.use_yaml ? lookup(local.config, "temporal", null) : var.temporal
  bedrock      = local.use_yaml ? lookup(local.config, "bedrock", null) : var.bedrock

  app_name = local.use_yaml ? lookup(local.config, "name", var.app_name) : var.app_name

  common_tags = merge(var.tags, {
    Team      = local.use_yaml ? lookup(local.config, "team", "unknown") : var.team
    Domain    = local.use_yaml ? lookup(local.config, "domain", "unknown") : var.domain
    Portfolio = local.use_yaml ? lookup(local.config, "portfolio", "unknown") : var.portfolio
    AppName   = local.app_name
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# S3 Buckets — terraform-aws-modules/s3-bucket/aws
#
# Guardrails: KMS encryption, public access blocked, versioning default on
# Naming: conservice-{env}-{app_name}-{key}
# -----------------------------------------------------------------------------

module "s3_buckets" {
  source   = "terraform-aws-modules/s3-bucket/aws"
  version  = "~> 5.7.0"
  for_each = local.buckets

  bucket = "${var.project}-${var.env}-${var.app_name}-${each.key}"

  versioning = {
    status = lookup(each.value, "versioning", true) ? "Enabled" : "Suspended"
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = var.kms_key_arn
      }
      bucket_key_enabled = true
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.app_name}-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# SQS Queues — native resources
#
# Guardrails: SQS-managed encryption, DLQ by default
# Naming: csvc-{env}-{region_code}-{app_name}-{key}-queue
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "dlqs" {
  for_each = { for k, v in local.queues : k => v if lookup(v, "dlq", true) }

  name                      = "${local.name_prefix}-${each.key}-dlq"
  message_retention_seconds = lookup(each.value, "dlq_retention_seconds", 1209600) # 14 days
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-dlq"
  })
}

resource "aws_sqs_queue" "queues" {
  for_each = local.queues

  name                       = "${local.name_prefix}-${each.key}-queue"
  visibility_timeout_seconds = lookup(each.value, "visibility_timeout", 30)
  message_retention_seconds  = lookup(each.value, "retention_seconds", 345600) # 4 days
  sqs_managed_sse_enabled    = true

  redrive_policy = lookup(each.value, "dlq", true) ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlqs[each.key].arn
    maxReceiveCount     = lookup(each.value, "max_receive_count", 5)
  }) : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-queue"
  })
}

# -----------------------------------------------------------------------------
# SNS Topics — native resources
#
# Guardrails: KMS encryption
# Naming: csvc-{env}-{region_code}-{app_name}-{key}-topic
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "topics" {
  for_each = local.topics

  name              = "${local.name_prefix}-${each.key}-topic"
  kms_master_key_id = var.kms_key_arn != null ? var.kms_key_arn : "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-topic"
  })
}

# -----------------------------------------------------------------------------
# Secrets Manager — native resources
#
# Creates secret containers. Values are populated via CLI or console post-apply.
# ESO syncs these into K8s via ExternalSecret manifests (managed in k8s-apps repo).
# Naming: {app_name}/{key}
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "secrets" {
  for_each = local.secrets

  name        = "${var.app_name}/${each.key}"
  description = lookup(each.value, "description", "Secret for ${var.app_name}")
  kms_key_id  = var.kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${var.app_name}/${each.key}"
  })
}

# -----------------------------------------------------------------------------
# App Secrets — two secrets, one k8s Secret
#
# {app}/config   — manual values (API keys, OAuth creds). ignore_changes
#                  prevents TF from overwriting. Seeded with REPLACE_ME.
# {app}/computed — TF-managed values (DATABASE_URL, TEMPORAL_CLOUD_API_KEY).
#                  No ignore_changes — TF always writes current values.
#
# ESO uses two dataFrom.extract entries that merge into one k8s Secret.
# Pods see one flat set of env vars. Adding/removing keys in either
# Secrets Manager secret requires no ExternalSecret changes.
# -----------------------------------------------------------------------------

locals {
  # Manual values: REPLACE_ME placeholders
  manual_config     = { for k in var.app_config_keys : k => "REPLACE_ME" }
  create_app_config = length(var.app_config_keys) > 0
}

resource "aws_secretsmanager_secret" "app_config" {
  count = local.create_app_config ? 1 : 0

  name        = "${var.app_name}/config"
  description = "Application secrets for ${var.app_name} (manual values — populate after apply)"
  kms_key_id  = var.kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${var.app_name}/config"
  })
}

resource "aws_secretsmanager_secret_version" "app_config" {
  count = local.create_app_config ? 1 : 0

  secret_id     = aws_secretsmanager_secret.app_config[0].id
  secret_string = jsonencode(local.manual_config)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Databases — conservice-app-database sub-module
#
# Creates PostgreSQL databases + IAM-auth roles inside shared Aurora cluster.
# -----------------------------------------------------------------------------

module "databases" {
  source   = "../conservice-app-database"
  for_each = var.enable_databases ? local.databases : {}

  database_name = each.key
  service_role  = lookup(each.value, "service_role", "${replace(var.app_name, "-", "_")}_svc")
  team_role     = lookup(each.value, "team_role", "")
  extensions    = lookup(each.value, "extensions", [])

  app_permissions  = lookup(each.value, "app_permissions", ["SELECT", "INSERT", "UPDATE", "DELETE"])
  team_permissions = lookup(each.value, "team_permissions", ["SELECT"])
  admin_groups     = lookup(each.value, "admin_groups", [])
  readonly_groups  = lookup(each.value, "readonly_groups", [])
  admin_users      = lookup(each.value, "admin_users", [])
  readonly_users   = lookup(each.value, "readonly_users", [])
  connection_limit = lookup(each.value, "connection_limit", -1)

  additional_readonly_roles = lookup(each.value, "additional_readonly_roles", [])
}

# -----------------------------------------------------------------------------
# Temporal Cloud — namespace, search attributes, service account + API key
#
# Creates a per-app Temporal Cloud namespace when temporal block is present.
# Calls the conservice-temporal sub-module.
# -----------------------------------------------------------------------------

locals {
  create_temporal = local.temporal != null

  temporal_search_attributes = local.create_temporal ? lookup(local.temporal, "search_attributes", {}) : {}
}

module "temporal" {
  source = "../conservice-temporal"
  count  = local.create_temporal ? 1 : 0

  app_name       = local.app_name
  env            = var.env
  regions        = lookup(local.temporal, "regions", ["aws-us-east-1"])
  retention_days = lookup(local.temporal, "retention_days", 30)
  api_key_auth   = lookup(local.temporal, "api_key_auth", true)

  enable_delete_protection = lookup(local.temporal, "enable_delete_protection", var.env == "prod")

  search_attributes = local.temporal_search_attributes

  create_service_account     = lookup(local.temporal, "create_service_account", true)
  service_account_permission = lookup(local.temporal, "service_account_permission", "write")
  api_key_expiry             = lookup(local.temporal, "api_key_expiry", "")

  store_api_key_in_secrets_manager = lookup(local.temporal, "store_api_key_in_secrets_manager", true)
  secrets_kms_key_arn              = var.kms_key_arn

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Pod Identity — auto-generated IAM role scoped to this app's resources
#
# Creates an IAM role with permissions for exactly the resources declared
# above (S3 buckets, SQS queues, SNS topics, Secrets Manager secrets,
# Aurora databases). Associates it with an EKS service account via Pod Identity.
#
# Enabled when pod_identity block is present in infra.yaml.
# -----------------------------------------------------------------------------

locals {
  create_pod_identity = local.pod_identity != null

  # Build IAM policy statements from declared resources
  s3_statements = length(local.buckets) > 0 ? [{
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = flatten([
      for k, _ in local.buckets : [
        module.s3_buckets[k].s3_bucket_arn,
        "${module.s3_buckets[k].s3_bucket_arn}/*",
      ]
    ])
  }] : []

  sqs_statements = length(local.queues) > 0 ? [{
    sid    = "SQSAccess"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [for k, v in aws_sqs_queue.queues : v.arn]
  }] : []

  sns_statements = length(local.topics) > 0 ? [{
    sid       = "SNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [for k, v in aws_sns_topic.topics : v.arn]
  }] : []

  # Collect all module-managed secret ARNs: explicit secrets + config + temporal
  all_secret_arns = concat(
    [for k, v in aws_secretsmanager_secret.secrets : v.arn],
    length(aws_secretsmanager_secret.app_config) > 0 ? [aws_secretsmanager_secret.app_config[0].arn] : [],
    length(module.temporal) > 0 && module.temporal[0].api_key_secret_arn != "" ? [module.temporal[0].api_key_secret_arn] : [],
  )

  secrets_statements = length(local.all_secret_arns) > 0 ? [{
    sid       = "SecretsManagerRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = local.all_secret_arns
  }] : []

  db_statements = length(local.databases) > 0 ? [{
    sid       = "AuroraIAMAuth"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = [for k, v in module.databases : "arn:aws:rds-db:${var.region}:${var.aws_account_id}:dbuser:*/${v.service_role_name}"]
  }] : []

  # KMS decrypt needed if using customer-managed KMS for S3/Secrets
  kms_statements = var.kms_key_arn != null ? [{
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [var.kms_key_arn]
  }] : []

  # Bedrock model invocation — added when bedrock block is present
  bedrock_model_ids = local.bedrock != null ? lookup(local.bedrock, "model_ids", []) : []

  bedrock_invoke_statements = length(local.bedrock_model_ids) > 0 ? [{
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = concat(
      [for m in local.bedrock_model_ids : "arn:aws:bedrock:${var.region}::foundation-model/${m}"],
      ["arn:aws:bedrock:${var.region}:${var.aws_account_id}:inference-profile/*"],
    )
  }] : []

  bedrock_guardrail_statements = local.bedrock != null && lookup(local.bedrock, "guardrails", false) ? [{
    sid       = "BedrockGuardrails"
    effect    = "Allow"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = ["arn:aws:bedrock:${var.region}:${var.aws_account_id}:guardrail/*"]
  }] : []

  bedrock_kb_statements = local.bedrock != null && lookup(local.bedrock, "knowledge_bases", false) ? [{
    sid       = "BedrockKnowledgeBases"
    effect    = "Allow"
    actions   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
    resources = ["arn:aws:bedrock:${var.region}:${var.aws_account_id}:knowledge-base/*"]
  }] : []

  # Use flatten instead of concat to avoid go-cty type mismatch panic
  # when some lists are empty with different inferred element types
  all_policy_statements = flatten([
    local.s3_statements,
    local.sqs_statements,
    local.sns_statements,
    local.secrets_statements,
    local.db_statements,
    local.kms_statements,
    local.bedrock_invoke_statements,
    local.bedrock_guardrail_statements,
    local.bedrock_kb_statements,
  ])
}

data "aws_iam_policy_document" "pod_identity_trust" {
  count = local.create_pod_identity ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pod_identity" {
  count = local.create_pod_identity ? 1 : 0

  dynamic "statement" {
    for_each = local.all_policy_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "pod_identity" {
  count = local.create_pod_identity ? 1 : 0

  name               = "${local.app_role_prefix}-pod-role"
  path               = "/apps/"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust[0].json

  tags = merge(local.common_tags, {
    Name = "${local.app_role_prefix}-pod-role"
  })
}

resource "aws_iam_policy" "pod_identity" {
  count = local.create_pod_identity ? 1 : 0

  name   = "${local.app_role_prefix}-pod-policy"
  path   = "/apps/"
  policy = data.aws_iam_policy_document.pod_identity[0].json

  tags = merge(local.common_tags, {
    Name = "${local.app_role_prefix}-pod-policy"
  })
}

resource "aws_iam_role_policy_attachment" "pod_identity" {
  count = local.create_pod_identity ? 1 : 0

  role       = aws_iam_role.pod_identity[0].name
  policy_arn = aws_iam_policy.pod_identity[0].arn
}

resource "aws_eks_pod_identity_association" "this" {
  count = local.create_pod_identity ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = lookup(local.pod_identity, "namespace", var.app_name)
  service_account = lookup(local.pod_identity, "service_account", var.app_name)
  role_arn        = aws_iam_role.pod_identity[0].arn
}

# -----------------------------------------------------------------------------
# ECR Repositories — created in the platform account via aws.ecr provider
#
# App repos live in apps/{app_name}-{image} namespace.
# Cross-account pull for EKS nodes, push for app CI roles.
# Created here (not in platform/global/ecr) so all app resources are
# self-contained — no SRE touchpoint for onboarding.
# -----------------------------------------------------------------------------

locals {
  ecr_repos = { for name in var.ecr_repos : name => "apps/${var.app_name}-${name}" }
}

resource "aws_ecr_repository" "app" {
  provider = aws.ecr
  for_each = local.ecr_repos

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.ecr_kms_key_arn != "" ? "KMS" : "AES256"
    kms_key         = var.ecr_kms_key_arn != "" ? var.ecr_kms_key_arn : null
  }

  tags = merge(local.common_tags, {
    Name = each.value
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  provider = aws.ecr
  for_each = local.ecr_repos

  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.ecr_image_retention_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.ecr_image_retention_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_repository_policy" "app_cross_account" {
  provider = aws.ecr
  for_each = length(var.ecr_cross_account_ids) > 0 ? local.ecr_repos : {}

  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = [for id in var.ecr_cross_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
        ]
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:role/eks/*"
          }
        }
      },
      {
        Sid    = "CrossAccountPush"
        Effect = "Allow"
        Principal = {
          AWS = [for id in var.ecr_cross_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:role/apps/*-ci-role"
          }
        }
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# CI Role — per-app IAM role for GitHub Actions
#
# Scoped to this app's resources only. GitHub Actions assumes this role
# (via OIDC → org role → assume this role) to:
#   - Run terraform plan/apply on this app's infra
#   - Push Docker images to this app's ECR repos
#   - Read/write this app's Terraform state
#
# Enabled when ci_role block is present in infra.yaml.
# -----------------------------------------------------------------------------

locals {
  create_ci_role = local.ci_role != null
  ci_github_org  = lookup(local.ci_role != null ? local.ci_role : {}, "github_org", "")
  ci_repo_name   = lookup(local.ci_role != null ? local.ci_role : {}, "repo_name", "${var.project}-app-${var.app_name}")
}

data "aws_iam_policy_document" "ci_trust" {
  count = local.create_ci_role ? 1 : 0

  # Trust the org-level GitHub OIDC role to assume this role.
  # Repo-level scoping is handled by the OIDC role's trust policy (sub claim).
  # Session tags are NOT available with OIDC — do not condition on PrincipalTag.
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [var.github_oidc_provider_arn]
    }
  }
}

data "aws_iam_policy_document" "ci" {
  count = local.create_ci_role ? 1 : 0

  # Terraform state access (this app's state key only)
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}",
      "arn:aws:s3:::${var.tf_state_bucket}/*/apps/${var.app_name}/*",
    ]
  }

  # ECR push (this app's repos only)
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
    ]
    resources = ["arn:aws:ecr:${var.region}:${var.ecr_account_id}:repository/apps/${var.app_name}-*"]
  }

  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Same resource permissions as the pod identity role — CI needs to
  # create/manage these resources via Terraform
  dynamic "statement" {
    for_each = local.all_policy_statements
    content {
      sid       = "CI${statement.value.sid}"
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }

  # Secrets Manager write — CI can populate secret values
  dynamic "statement" {
    for_each = length(local.all_secret_arns) > 0 ? [1] : []
    content {
      sid    = "CISecretsWrite"
      effect = "Allow"
      actions = [
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:TagResource",
      ]
      resources = local.all_secret_arns
    }
  }

  # EKS Pod Identity association management
  dynamic "statement" {
    for_each = local.create_pod_identity ? [1] : []
    content {
      sid    = "CIEKSPodIdentity"
      effect = "Allow"
      actions = [
        "eks:CreatePodIdentityAssociation",
        "eks:DeletePodIdentityAssociation",
        "eks:DescribePodIdentityAssociation",
        "eks:ListPodIdentityAssociations",
      ]
      resources = ["*"]
    }
  }

  # Org state bucket read — for identity-center remote state (SSO instance ARN, permission sets)
  dynamic "statement" {
    for_each = local.create_sso ? [1] : []
    content {
      sid    = "CIOrgStateRead"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:ListBucket",
      ]
      resources = [
        "arn:aws:s3:::conservice-tf-state-organization",
        "arn:aws:s3:::conservice-tf-state-organization/organization/global/identity-center/*",
      ]
    }
  }

  # Cross-account SSO assignment role assume
  dynamic "statement" {
    for_each = local.create_sso ? [1] : []
    content {
      sid    = "CISSOAssume"
      effect = "Allow"
      actions = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
      resources = ["arn:aws:iam::896476316505:role/sso/${var.project}-org-sso-assignment-role"]
    }
  }

  # IAM management for this app's roles only
  statement {
    sid    = "CIIAMManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/apps/${local.app_role_prefix}-*",
      "arn:aws:iam::${var.aws_account_id}:policy/apps/${local.app_role_prefix}-*",
    ]
  }
}

resource "aws_iam_role" "ci" {
  count = local.create_ci_role ? 1 : 0

  name               = "${local.app_role_prefix}-ci-role"
  path               = "/apps/"
  assume_role_policy = data.aws_iam_policy_document.ci_trust[0].json

  tags = merge(local.common_tags, {
    Name = "${local.app_role_prefix}-ci-role"
  })
}

resource "aws_iam_policy" "ci" {
  count = local.create_ci_role ? 1 : 0

  name   = "${local.app_role_prefix}-ci-policy"
  path   = "/apps/"
  policy = data.aws_iam_policy_document.ci[0].json

  tags = merge(local.common_tags, {
    Name = "${local.app_role_prefix}-ci-policy"
  })
}

resource "aws_iam_role_policy_attachment" "ci" {
  count = local.create_ci_role ? 1 : 0

  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci[0].arn
}

# -----------------------------------------------------------------------------
# SSO Identity Center — Per-App Permission Sets + Assignments (via org provider)
#
# Creates app-scoped permission sets (DB-{app}-Admin, DB-{app}-ReadOnly) with
# rds-db:connect restricted to this app's database users only. Assignments
# bind the app's Google groups to these permission sets on target accounts.
# terraform destroy removes both permission sets and assignments — no orphans.
# -----------------------------------------------------------------------------

locals {
  create_sso = var.sso_access != null
  # Database user prefix for IAM scoping (app-name with hyphens → underscores)
  db_user_prefix = replace(var.app_name, "-", "_")
}

# --- Per-app permission sets (scoped to this app's DB users only) ---

resource "aws_ssoadmin_permission_set" "db_admin" {
  provider = aws.org
  count    = local.create_sso ? 1 : 0

  name             = "DB-${var.app_name}-Admin"
  description      = "Database admin for ${var.app_name} — rds-db:connect scoped to ${local.db_user_prefix}_* users"
  instance_arn     = var.sso_instance_arn
  session_duration = "PT4H"

  tags = merge(local.common_tags, {
    Name = "DB-${var.app_name}-Admin"
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "db_admin" {
  provider = aws.org
  count    = local.create_sso ? 1 : 0

  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.db_admin[0].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RDSIAMConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["arn:aws:rds-db:*:*:dbuser:*/${local.db_user_prefix}_*"]
      },
      {
        Sid    = "RDSDescribe"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusterEndpoints",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_ssoadmin_permission_set" "db_readonly" {
  provider = aws.org
  count    = local.create_sso ? 1 : 0

  name             = "DB-${var.app_name}-ReadOnly"
  description      = "Database readonly for ${var.app_name} — rds-db:connect scoped to ${local.db_user_prefix}_* users"
  instance_arn     = var.sso_instance_arn
  session_duration = "PT4H"

  tags = merge(local.common_tags, {
    Name = "DB-${var.app_name}-ReadOnly"
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "db_readonly" {
  provider = aws.org
  count    = local.create_sso ? 1 : 0

  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.db_readonly[0].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RDSIAMConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["arn:aws:rds-db:*:*:dbuser:*/${local.db_user_prefix}_*"]
      },
      {
        Sid    = "RDSDescribe"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusterEndpoints",
        ]
        Resource = ["*"]
      },
    ]
  })
}

# --- Group lookups ---

data "aws_identitystore_group" "sso_groups" {
  provider = aws.org

  for_each          = local.create_sso ? toset([var.sso_access.admin_group, var.sso_access.readonly_group]) : toset([])
  identity_store_id = var.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

# --- Assignments (group → per-app permission set → target accounts) ---

locals {
  sso_assignments = local.create_sso ? flatten([
    for account_id in try(var.sso_access.account_ids, []) : [
      {
        key                = "${var.sso_access.admin_group}-admin-${account_id}"
        group_name         = var.sso_access.admin_group
        permission_set_arn = aws_ssoadmin_permission_set.db_admin[0].arn
        account_id         = account_id
      },
      {
        key                = "${var.sso_access.readonly_group}-readonly-${account_id}"
        group_name         = var.sso_access.readonly_group
        permission_set_arn = aws_ssoadmin_permission_set.db_readonly[0].arn
        account_id         = account_id
      },
    ]
  ]) : []
}

resource "aws_ssoadmin_account_assignment" "app" {
  provider = aws.org

  for_each = {
    for a in local.sso_assignments : a.key => a
  }

  instance_arn       = var.sso_instance_arn
  permission_set_arn = each.value.permission_set_arn

  principal_id   = data.aws_identitystore_group.sso_groups[each.value.group_name].group_id
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
}
