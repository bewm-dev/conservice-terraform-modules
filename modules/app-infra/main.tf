# -----------------------------------------------------------------------------
# App-Level Infrastructure Root Module
#
# This module reads YAML config from an app's infra/ directory and provisions
# AWS resources using guardrail modules. The config merge follows the same
# 3-layer pattern as Cybertron:
#
#   1. infra/base.yaml          — team, domain, portfolio (shared across envs)
#   2. infra/<resource>.yaml    — resource defaults (e.g. database.yaml, s3.yaml)
#   3. infra/envs/<env>.yaml    — environment overrides (merged on top)
#
# Dev teams only edit YAML. This module + CI handles the rest.
# -----------------------------------------------------------------------------

locals {
  # Read base config
  base = yamldecode(file("${var.config_path}/base.yaml"))

  # Read per-resource configs (if they exist)
  has_databases = fileexists("${var.config_path}/database.yaml")
  has_buckets   = fileexists("${var.config_path}/s3.yaml")
  has_queues    = fileexists("${var.config_path}/sqs.yaml")
  has_topics    = fileexists("${var.config_path}/sns.yaml")

  database_defaults = local.has_databases ? yamldecode(file("${var.config_path}/database.yaml")) : {}
  bucket_defaults   = local.has_buckets ? yamldecode(file("${var.config_path}/s3.yaml")) : {}
  queue_defaults    = local.has_queues ? yamldecode(file("${var.config_path}/sqs.yaml")) : {}
  topic_defaults    = local.has_topics ? yamldecode(file("${var.config_path}/sns.yaml")) : {}

  # Read environment override (if it exists)
  env_override_path = "${var.config_path}/envs/${var.env}.yaml"
  has_env_override  = fileexists(local.env_override_path)
  env_override      = local.has_env_override ? yamldecode(file(local.env_override_path)) : {}

  # Merge: resource defaults ← env overrides (env wins)
  databases = lookup(local.env_override, "databases", lookup(local.database_defaults, "databases", {}))
  buckets   = lookup(local.env_override, "buckets", lookup(local.bucket_defaults, "buckets", {}))
  queues    = lookup(local.env_override, "queues", lookup(local.queue_defaults, "queues", {}))
  topics    = lookup(local.env_override, "topics", lookup(local.topic_defaults, "topics", {}))

  # Common tags from base config
  app_tags = merge(var.tags, {
    Team      = lookup(local.base, "team", "unknown")
    Domain    = lookup(local.base, "domain", "unknown")
    Portfolio = lookup(local.base, "portfolio", "unknown")
    AppName   = lookup(local.base, "name", var.app_name)
  })
}

# -----------------------------------------------------------------------------
# Databases — calls aurora-database guardrail module per database
# -----------------------------------------------------------------------------

module "databases" {
  source   = "../aurora-database"
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

# -----------------------------------------------------------------------------
# S3 Buckets — guardrail: encryption, public access blocked, versioning
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets

  bucket = "conservice-${var.env}-${var.app_name}-${each.key}"

  tags = merge(local.app_tags, {
    Name = "conservice-${var.env}-${var.app_name}-${each.key}"
  })
}

resource "aws_s3_bucket_versioning" "buckets" {
  for_each = { for k, v in local.buckets : k => v if lookup(v, "versioning", true) }

  bucket = aws_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = local.buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = local.buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# SQS Queues — guardrail: encryption, DLQ, tags
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "dlqs" {
  for_each = { for k, v in local.queues : k => v if lookup(v, "dlq", true) }

  name                      = "conservice-${var.env}-${var.app_name}-${each.key}-dlq"
  message_retention_seconds = lookup(each.value, "dlq_retention_seconds", 1209600) # 14 days
  sqs_managed_sse_enabled   = true

  tags = merge(local.app_tags, {
    Name = "conservice-${var.env}-${var.app_name}-${each.key}-dlq"
  })
}

resource "aws_sqs_queue" "queues" {
  for_each = local.queues

  name                       = "conservice-${var.env}-${var.app_name}-${each.key}"
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

  tags = merge(local.app_tags, {
    Name = "conservice-${var.env}-${var.app_name}-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# SNS Topics — guardrail: encryption, tags
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "topics" {
  for_each = local.topics

  name              = "conservice-${var.env}-${var.app_name}-${each.key}"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.app_tags, {
    Name = "conservice-${var.env}-${var.app_name}-${each.key}"
  })
}
