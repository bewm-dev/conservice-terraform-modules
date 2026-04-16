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
# Naming (key suffix dropped when only one resource of that type):
#   S3 buckets:     {project}-{env}-{app_name}[-{key}]  (global namespace)
#   SQS queues:     {prefix}-{env}-{region_code}-{app_name}[-{key}]-queue
#   SNS topics:     {prefix}-{env}-{region_code}-{app_name}[-{key}]-topic
#   EventBridge:    {prefix}-{env}-{region_code}-{app_name}[-{key}]
#   Step Functions: {prefix}-{env}-{region_code}-{app_name}[-{key}]
#   DynamoDB:       {prefix}-{env}-{region_code}-{app_name}[-{key}]
#   Secrets:        {app_name}/{key}
#   Databases:      key becomes the database name in shared Aurora
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
  buckets        = local.use_yaml ? lookup(local.env_override, "buckets", lookup(local.config, "buckets", {})) : var.buckets
  queues         = local.use_yaml ? lookup(local.env_override, "queues", lookup(local.config, "queues", {})) : var.queues
  topics         = local.use_yaml ? lookup(local.env_override, "topics", lookup(local.config, "topics", {})) : var.topics
  event_buses    = local.use_yaml ? lookup(local.env_override, "event_buses", lookup(local.config, "event_buses", {})) : var.event_buses
  state_machines = local.use_yaml ? lookup(local.env_override, "state_machines", lookup(local.config, "state_machines", {})) : var.state_machines
  tables         = local.use_yaml ? lookup(local.env_override, "tables", lookup(local.config, "tables", {})) : var.tables
  databases      = local.use_yaml ? lookup(local.env_override, "databases", lookup(local.config, "databases", {})) : var.databases
  secrets        = local.use_yaml ? lookup(local.env_override, "secrets", lookup(local.config, "secrets", {})) : var.secrets
  pod_identity   = local.use_yaml ? lookup(local.config, "pod_identity", null) : var.pod_identity
  ci_role        = local.use_yaml ? lookup(local.config, "ci_role", null) : var.ci_role
  temporal       = local.use_yaml ? lookup(local.config, "temporal", null) : var.temporal
  bedrock        = local.use_yaml ? lookup(local.config, "bedrock", null) : var.bedrock

  # EventBridge: flatten rules from all buses into a flat list for for_each
  event_bus_rules = flatten([
    for bus_key, bus in local.event_buses : [
      for rule_key, rule in lookup(bus, "rules", {}) : {
        bus_key     = bus_key
        rule_key    = rule_key
        pattern     = rule.pattern
        description = lookup(rule, "description", "")
      }
    ]
  ])

  # DynamoDB: build attribute definitions from hash_key, range_key, and GSI keys
  table_attributes = {
    for tbl_key, tbl in local.tables : tbl_key => distinct(concat(
      [{ name = lookup(tbl, "hash_key", "pk"), type = lookup(tbl, "hash_key_type", "S") }],
      lookup(tbl, "range_key", null) != null ? [{ name = tbl.range_key, type = lookup(tbl, "range_key_type", "S") }] : [],
      flatten([
        for gsi_key, gsi in lookup(tbl, "gsi", {}) : concat(
          [{ name = gsi.hash_key, type = lookup(gsi, "hash_key_type", "S") }],
          lookup(gsi, "range_key", null) != null ? [{ name = gsi.range_key, type = lookup(gsi, "range_key_type", "S") }] : [],
        )
      ])
    ))
  }

  app_name = local.use_yaml ? lookup(local.config, "name", var.app_name) : var.app_name

  common_tags = merge(var.tags, {
    Team      = local.use_yaml ? lookup(local.config, "team", "unknown") : var.team
    Domain    = local.use_yaml ? lookup(local.config, "domain", "unknown") : var.domain
    Portfolio = local.use_yaml ? lookup(local.config, "portfolio", "unknown") : var.portfolio
    AppName   = local.app_name
    ManagedBy = "terraform"
  })

  # ---------------------------------------------------------------------------
  # Computed resource names — drop key suffix when only one resource of a type
  # e.g., single S3 bucket: "conservice-stg-myapp" not "conservice-stg-myapp-data"
  # ---------------------------------------------------------------------------

  s3_bucket_names = {
    for k, v in local.buckets : k => length(local.buckets) == 1 ? "${var.project}-${var.env}-${var.app_name}" : "${var.project}-${var.env}-${var.app_name}-${k}"
  }

  sqs_queue_names = {
    for k, v in local.queues : k => length(local.queues) == 1 ? "${local.name_prefix}-queue" : "${local.name_prefix}-${k}-queue"
  }

  sqs_dlq_names = {
    for k, v in local.queues : k => length(local.queues) == 1 ? "${local.name_prefix}-dlq" : "${local.name_prefix}-${k}-dlq"
  }

  sns_topic_names = {
    for k, v in local.topics : k => length(local.topics) == 1 ? "${local.name_prefix}-topic" : "${local.name_prefix}-${k}-topic"
  }

  event_bus_names = {
    for k, v in local.event_buses : k => length(local.event_buses) == 1 ? local.name_prefix : "${local.name_prefix}-${k}"
  }

  event_rule_names = {
    for item in local.event_bus_rules : "${item.bus_key}.${item.rule_key}" => length(local.event_buses) == 1 ? "${local.name_prefix}-${item.rule_key}" : "${local.name_prefix}-${item.bus_key}-${item.rule_key}"
  }

  sfn_names = {
    for k, v in local.state_machines : k => length(local.state_machines) == 1 ? local.name_prefix : "${local.name_prefix}-${k}"
  }

  sfn_role_names = {
    for k, v in local.state_machines : k => length(local.state_machines) == 1 ? "${local.app_role_prefix}-sfn-role" : "${local.app_role_prefix}-sfn-${k}-role"
  }

  dynamodb_names = {
    for k, v in local.tables : k => length(local.tables) == 1 ? local.name_prefix : "${local.name_prefix}-${k}"
  }
}

# -----------------------------------------------------------------------------
# S3 Buckets — terraform-aws-modules/s3-bucket/aws
#
# Guardrails: KMS encryption, public access blocked, versioning default on
# Naming: conservice-{env}-{app_name}[-{key}] (key omitted for single bucket)
# -----------------------------------------------------------------------------

module "s3_buckets" {
  source   = "terraform-aws-modules/s3-bucket/aws"
  version  = "~> 5.7.0"
  for_each = local.buckets

  bucket        = local.s3_bucket_names[each.key]
  force_destroy = var.s3_force_destroy

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
    Name = local.s3_bucket_names[each.key]
  })
}

# -----------------------------------------------------------------------------
# SQS Queues — native resources
#
# Guardrails: SQS-managed encryption, DLQ by default
# Naming: csvc-{env}-{region_code}-{app_name}[-{key}]-queue (key omitted for single queue)
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "dlqs" {
  for_each = { for k, v in local.queues : k => v if lookup(v, "dlq", true) }

  name                      = local.sqs_dlq_names[each.key]
  message_retention_seconds = lookup(each.value, "dlq_retention_seconds", 1209600) # 14 days
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name = local.sqs_dlq_names[each.key]
  })
}

resource "aws_sqs_queue" "queues" {
  for_each = local.queues

  name                       = local.sqs_queue_names[each.key]
  visibility_timeout_seconds = lookup(each.value, "visibility_timeout", 30)
  message_retention_seconds  = lookup(each.value, "retention_seconds", 345600) # 4 days
  sqs_managed_sse_enabled    = true

  redrive_policy = lookup(each.value, "dlq", true) ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlqs[each.key].arn
    maxReceiveCount     = lookup(each.value, "max_receive_count", 5)
  }) : null

  tags = merge(local.common_tags, {
    Name = local.sqs_queue_names[each.key]
  })
}

# -----------------------------------------------------------------------------
# SNS Topics — native resources
#
# Guardrails: KMS encryption
# Naming: csvc-{env}-{region_code}-{app_name}[-{key}]-topic (key omitted for single topic)
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "topics" {
  for_each = local.topics

  name              = local.sns_topic_names[each.key]
  kms_master_key_id = var.kms_key_arn != null ? var.kms_key_arn : "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = local.sns_topic_names[each.key]
  })
}

# -----------------------------------------------------------------------------
# EventBridge — native resources
#
# Guardrails: Custom event bus per app (never use the default bus)
# Naming: csvc-{env}-{region_code}-{app_name}[-{key}] (key omitted for single bus)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_bus" "buses" {
  for_each = local.event_buses

  name = local.event_bus_names[each.key]

  tags = merge(local.common_tags, {
    Name = local.event_bus_names[each.key]
  })
}

resource "aws_cloudwatch_event_rule" "rules" {
  for_each = { for item in local.event_bus_rules : "${item.bus_key}.${item.rule_key}" => item }

  name           = local.event_rule_names["${each.value.bus_key}.${each.value.rule_key}"]
  event_bus_name = aws_cloudwatch_event_bus.buses[each.value.bus_key].name
  event_pattern  = jsonencode(each.value.pattern)
  description    = lookup(each.value, "description", "Rule ${each.value.rule_key} on bus ${each.value.bus_key}")

  tags = merge(local.common_tags, {
    Name = local.event_rule_names["${each.value.bus_key}.${each.value.rule_key}"]
  })
}

# -----------------------------------------------------------------------------
# Step Functions — native resources
#
# Guardrails: CloudWatch logging, Express or Standard type
# Naming: csvc-{env}-{region_code}-{app_name}[-{key}] (key omitted for single state machine)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sfn" {
  for_each = local.state_machines

  name              = "/aws/vendedlogs/states/${local.sfn_names[each.key]}"
  retention_in_days = lookup(each.value, "log_retention_days", 30)

  tags = merge(local.common_tags, {
    Name = local.sfn_names[each.key]
  })
}

resource "aws_iam_role" "sfn" {
  for_each = local.state_machines

  name = local.sfn_role_names[each.key]
  path = "/apps/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action = ["sts:AssumeRole"]
    }]
  })

  tags = merge(local.common_tags, {
    Name = local.sfn_role_names[each.key]
  })
}

resource "aws_iam_role_policy" "sfn_logs" {
  for_each = local.state_machines

  name = "cloudwatch-logs"
  role = aws_iam_role.sfn[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_sfn_state_machine" "machines" {
  for_each = local.state_machines

  name     = local.sfn_names[each.key]
  role_arn = aws_iam_role.sfn[each.key].arn
  type     = upper(lookup(each.value, "type", "STANDARD"))

  definition = lookup(each.value, "definition", jsonencode({
    Comment = "Placeholder — replace with your workflow definition"
    StartAt = "Pass"
    States  = { Pass = { Type = "Pass", End = true } }
  }))

  logging_configuration {
    log_destination = "${aws_cloudwatch_log_group.sfn[each.key].arn}:*"
    include_execution_data = lookup(each.value, "log_execution_data", true)
    level                  = lookup(each.value, "log_level", "ALL")
  }

  tags = merge(local.common_tags, {
    Name = local.sfn_names[each.key]
  })
}

# -----------------------------------------------------------------------------
# DynamoDB Tables — native resources
#
# Guardrails: encryption at rest (KMS or AWS-owned), point-in-time recovery on by default
# Naming: csvc-{env}-{region_code}-{app_name}[-{key}] (key omitted for single table)
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "tables" {
  for_each = local.tables

  name         = local.dynamodb_names[each.key]
  billing_mode = upper(lookup(each.value, "billing_mode", "PAY_PER_REQUEST"))
  hash_key     = lookup(each.value, "hash_key", "pk")
  range_key    = lookup(each.value, "range_key", null)

  # Primary key attributes — always include hash_key, optionally range_key
  dynamic "attribute" {
    for_each = local.table_attributes[each.key]
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # Global secondary indexes
  dynamic "global_secondary_index" {
    for_each = lookup(each.value, "gsi", {})
    content {
      name            = global_secondary_index.key
      hash_key        = global_secondary_index.value.hash_key
      range_key       = lookup(global_secondary_index.value, "range_key", null)
      projection_type = lookup(global_secondary_index.value, "projection_type", "ALL")
    }
  }

  point_in_time_recovery {
    enabled = lookup(each.value, "point_in_time_recovery", true)
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  ttl {
    attribute_name = lookup(each.value, "ttl_attribute", "")
    enabled        = lookup(each.value, "ttl_attribute", "") != ""
  }

  deletion_protection_enabled = lookup(each.value, "deletion_protection", false)

  tags = merge(local.common_tags, {
    Name = local.dynamodb_names[each.key]
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

  name                    = "${var.app_name}/${each.key}"
  description             = lookup(each.value, "description", "Secret for ${var.app_name}")
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secrets_recovery_window_days

  tags = merge(local.common_tags, {
    Name = "${var.app_name}/${each.key}"
  })
}

# -----------------------------------------------------------------------------
# App Config Secret — {app}/config
#
# Manual/external values only (API keys, OAuth creds, third-party tokens).
# TF seeds REPLACE_ME placeholders on first apply; ignore_changes prevents
# overwriting manual updates.
#
# ESO merges this with module-owned secrets into one k8s Secret:
#   {app}/config              — manual values (this resource, dataFrom.extract)
#   temporal/{app}-{env}/...  — Temporal sub-module owns these (overlay patch)
#   aurora/...                — Aurora sub-module owns these (overlay patch)
#
# Each secret has exactly one owner. No manual copying between secrets.
# Non-secret env-specific values (DATABASE_URL, AWS_REGION) go in ConfigMap
# overlays, not Secrets Manager.
# -----------------------------------------------------------------------------

locals {
  # Manual values: REPLACE_ME placeholders
  manual_config     = { for k in var.app_config_keys : k => "REPLACE_ME" }
  create_app_config = length(var.app_config_keys) > 0
}

# Restore secret from pending deletion if it exists (handles rapid teardown → re-scaffold)
resource "terraform_data" "restore_app_config_secret" {
  count = local.create_app_config ? 1 : 0

  input = "${var.app_name}/config"

  provisioner "local-exec" {
    command = "aws secretsmanager restore-secret --secret-id '${var.app_name}/config' 2>/dev/null || true"
  }
}

resource "aws_secretsmanager_secret" "app_config" {
  count = local.create_app_config ? 1 : 0

  name                    = "${var.app_name}/config"
  description             = "Application secrets for ${var.app_name} (manual values — populate after apply)"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "${var.app_name}/config"
  })

  depends_on = [terraform_data.restore_app_config_secret]
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
# above (S3 buckets, SQS queues, SNS topics, EventBridge, Step Functions,
# DynamoDB tables, Secrets Manager secrets, Aurora databases).
# Associates it with an EKS service account via Pod Identity.
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

  eventbridge_statements = length(local.event_buses) > 0 ? [{
    sid    = "EventBridgePutEvents"
    effect = "Allow"
    actions = [
      "events:PutEvents",
    ]
    resources = [for k, v in aws_cloudwatch_event_bus.buses : v.arn]
  }] : []

  sfn_statements = length(local.state_machines) > 0 ? [{
    sid    = "StepFunctionsExecute"
    effect = "Allow"
    actions = [
      "states:StartExecution",
      "states:StartSyncExecution",
      "states:DescribeExecution",
      "states:StopExecution",
      "states:ListExecutions",
    ]
    resources = [for k, v in aws_sfn_state_machine.machines : v.arn]
  }] : []

  dynamodb_statements = length(local.tables) > 0 ? [{
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
    ]
    resources = flatten([
      for k, v in aws_dynamodb_table.tables : [
        v.arn,
        "${v.arn}/index/*",
      ]
    ])
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
    local.eventbridge_statements,
    local.sfn_statements,
    local.dynamodb_statements,
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
# ECR Repositories — managed centrally in the platform account's ECR component.
# See conservice-aws-platform/accounts/platform/global/ecr/
# Scaffold tool adds app repos; teardown removes them.

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
    resources = [
      "arn:aws:ecr:${var.region}:${var.ecr_account_id}:repository/apps/${var.app_name}",
      "arn:aws:ecr:${var.region}:${var.ecr_account_id}:repository/apps/${var.app_name}-*",
    ]
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

  # EKS Pod Identity association management — scoped to target cluster (M1)
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
      resources = [
        "arn:aws:eks:${var.region}:${var.aws_account_id}:cluster/${var.cluster_name}",
      ]
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
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/apps/${local.app_role_prefix}-*",
      "arn:aws:iam::${var.aws_account_id}:policy/apps/${local.app_role_prefix}-*",
    ]
  }

  # Attach/Detach restricted to app-scoped policies only (security audit C1).
  # Without this condition, iam:AttachRolePolicy only checks the role ARN —
  # an attacker could attach AdministratorAccess to an app role.
  statement {
    sid    = "CIIAMAttachPolicy"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/apps/${local.app_role_prefix}-*",
    ]
    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::${var.aws_account_id}:policy/apps/${local.app_role_prefix}-*",
      ]
    }
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
# SSO Identity Center
#
# Per-app permission sets + assignments are managed centrally in the org
# account's identity-center module, not here. This eliminates the need for
# an aws.org provider in app repos and avoids the race condition where both
# stg and prod try to create the same org-level permission sets.
#
# See: conservice-aws-platform/accounts/organization/global/identity-center/
# -----------------------------------------------------------------------------
