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
#   S3 buckets:  conservice-{env}-{app_name}-{key}  (global namespace)
#   SQS queues:  csvc-{env}-{region_code}-{app_name}-{key}-queue
#   SNS topics:  csvc-{env}-{region_code}-{app_name}-{key}-topic
#   Secrets:     conservice-{env}-{app_name}-{key}
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
  region_code = local.region_codes[var.region]
  name_prefix = "csvc-${var.env}-${local.region_code}-${var.app_name}"

  # ---------------------------------------------------------------------------
  # YAML config reading — single file + optional env override
  # ---------------------------------------------------------------------------

  config = yamldecode(file("${var.config_path}/infra.yaml"))

  env_override_path = "${var.config_path}/envs/${var.env}.yaml"
  has_env_override  = fileexists(local.env_override_path)
  env_override      = local.has_env_override ? yamldecode(file(local.env_override_path)) : {}

  # Merge: infra.yaml defaults ← env override (env wins for each resource type)
  buckets   = lookup(local.env_override, "buckets", lookup(local.config, "buckets", {}))
  queues    = lookup(local.env_override, "queues", lookup(local.config, "queues", {}))
  topics    = lookup(local.env_override, "topics", lookup(local.config, "topics", {}))
  databases = lookup(local.env_override, "databases", lookup(local.config, "databases", {}))
  secrets   = lookup(local.env_override, "secrets", lookup(local.config, "secrets", {}))

  # App metadata from config
  app_name = lookup(local.config, "name", var.app_name)

  # Common tags
  common_tags = merge(var.tags, {
    Team      = lookup(local.config, "team", "unknown")
    Domain    = lookup(local.config, "domain", "unknown")
    Portfolio = lookup(local.config, "portfolio", "unknown")
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

  bucket = "conservice-${var.env}-${var.app_name}-${each.key}"

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
    Name = "conservice-${var.env}-${var.app_name}-${each.key}"
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

  dynamic "redrive_policy" {
    for_each = lookup(each.value, "dlq", true) ? [1] : []
    content {
      dead_letter_target_arn = aws_sqs_queue.dlqs[each.key].arn
      max_receive_count      = lookup(each.value, "max_receive_count", 5)
    }
  }

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
# Naming: conservice-{env}-{app_name}-{key}
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "secrets" {
  for_each = local.secrets

  name        = "conservice-${var.env}-${var.app_name}-${each.key}"
  description = lookup(each.value, "description", "Secret for ${var.app_name}")
  kms_key_id  = var.kms_key_arn

  tags = merge(local.common_tags, {
    Name = "conservice-${var.env}-${var.app_name}-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# Databases — conservice-app-database sub-module
#
# Creates PostgreSQL databases + IAM-auth roles inside shared Aurora cluster.
# -----------------------------------------------------------------------------

module "databases" {
  source   = "../conservice-app-database"
  for_each = local.databases

  database_name = each.key
  service_role  = lookup(each.value, "service_role", "${var.app_name}-${each.key}-svc")
  team_role     = lookup(each.value, "team_role", "")
  extensions    = lookup(each.value, "extensions", [])

  app_permissions  = lookup(each.value, "app_permissions", ["SELECT", "INSERT", "UPDATE", "DELETE"])
  team_permissions = lookup(each.value, "team_permissions", ["SELECT"])
  admin_users      = lookup(each.value, "admin_users", [])
  readonly_users   = lookup(each.value, "readonly_users", [])
  connection_limit = lookup(each.value, "connection_limit", -1)

  additional_readonly_roles = lookup(each.value, "additional_readonly_roles", [])
}
