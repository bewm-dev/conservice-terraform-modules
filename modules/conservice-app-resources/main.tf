# -----------------------------------------------------------------------------
# conservice-app-resources
#
# Provisions app-level AWS resources from YAML config. Dev teams edit YAML
# files in their app repo's infra/ directory; this module + CI handles the rest.
#
# Config merge (3 layers):
#   1. infra/base.yaml          — team, domain, portfolio (required)
#   2. infra/<resource>.yaml    — resource defaults (s3.yaml, sqs.yaml, etc.)
#   3. infra/envs/<env>.yaml    — environment overrides (merged on top)
#
# Naming convention: csvc-{env}-{region_code}-{app_name}-{resource_key}-{type}
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
  # YAML config reading
  # ---------------------------------------------------------------------------

  base = yamldecode(file("${var.config_path}/base.yaml"))

  has_buckets   = fileexists("${var.config_path}/s3.yaml")
  has_queues    = fileexists("${var.config_path}/sqs.yaml")
  has_topics    = fileexists("${var.config_path}/sns.yaml")
  has_databases = fileexists("${var.config_path}/database.yaml")

  bucket_defaults   = local.has_buckets ? yamldecode(file("${var.config_path}/s3.yaml")) : {}
  queue_defaults    = local.has_queues ? yamldecode(file("${var.config_path}/sqs.yaml")) : {}
  topic_defaults    = local.has_topics ? yamldecode(file("${var.config_path}/sns.yaml")) : {}
  database_defaults = local.has_databases ? yamldecode(file("${var.config_path}/database.yaml")) : {}

  env_override_path = "${var.config_path}/envs/${var.env}.yaml"
  has_env_override  = fileexists(local.env_override_path)
  env_override      = local.has_env_override ? yamldecode(file(local.env_override_path)) : {}

  # Merge: resource defaults ← env overrides (env wins)
  buckets   = lookup(local.env_override, "buckets", lookup(local.bucket_defaults, "buckets", {}))
  queues    = lookup(local.env_override, "queues", lookup(local.queue_defaults, "queues", {}))
  topics    = lookup(local.env_override, "topics", lookup(local.topic_defaults, "topics", {}))
  databases = lookup(local.env_override, "databases", lookup(local.database_defaults, "databases", {}))

  # Common tags from base config
  common_tags = merge(var.tags, {
    Team      = lookup(local.base, "team", "unknown")
    Domain    = lookup(local.base, "domain", "unknown")
    Portfolio = lookup(local.base, "portfolio", "unknown")
    AppName   = lookup(local.base, "name", var.app_name)
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# S3 Buckets — terraform-aws-modules/s3-bucket/aws
#
# Guardrails: KMS encryption, public access blocked, versioning default on
# Naming: conservice-{env}-{app_name}-{bucket_key}
# (S3 uses conservice- prefix per naming convention — global namespace)
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
# SQS Queues — native resources (simple enough, no community module needed)
#
# Guardrails: SQS-managed encryption, DLQ by default, consistent naming
# Naming: csvc-{env}-{region_code}-{app_name}-{queue_key}-queue
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
# Guardrails: KMS encryption, consistent naming
# Naming: csvc-{env}-{region_code}-{app_name}-{topic_key}-topic
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
