# -----------------------------------------------------------------------------
# conservice-temporal
#
# Provisions Temporal Cloud resources for an application:
#   - Namespace (per-app, per-env isolation)
#   - Custom search attributes
#   - Service account with namespace-scoped access + API key
#   - Optionally stores the API key in AWS Secrets Manager
#
# Auth: The caller must configure the temporalcloud provider with an API key
# that has account-level admin access (to create namespaces + service accounts).
#
# Naming: {app_name}-{env} (e.g., rates-agent-prod)
# -----------------------------------------------------------------------------

locals {
  namespace_name = "${var.app_name}-${var.env}"
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "temporalcloud_namespace" "this" {
  name           = local.namespace_name
  regions        = var.regions
  retention_days = var.retention_days
  api_key_auth   = var.api_key_auth

  namespace_lifecycle {
    enable_delete_protection = var.enable_delete_protection
  }
}

# -----------------------------------------------------------------------------
# Search Attributes
# -----------------------------------------------------------------------------

resource "temporalcloud_namespace_search_attribute" "this" {
  for_each = var.search_attributes

  namespace_id = temporalcloud_namespace.this.id
  name         = each.key
  type         = lower(each.value)
}

# -----------------------------------------------------------------------------
# Service Account + API Key
#
# Namespace-scoped: the service account can only access this namespace.
# The API key token is sensitive and only available at creation time —
# store it in Secrets Manager immediately.
# -----------------------------------------------------------------------------

resource "temporalcloud_service_account" "this" {
  count = var.create_service_account ? 1 : 0

  name        = "${local.namespace_name}-worker"
  description = "Service account for ${var.app_name} workers in ${var.env}"

  namespace_scoped_access {
    namespace_id = temporalcloud_namespace.this.id
    permission   = var.service_account_permission
  }
}

resource "temporalcloud_apikey" "this" {
  count = var.create_service_account && var.api_key_expiry != "" ? 1 : 0

  display_name = "${local.namespace_name}-api-key"
  description  = "API key for ${var.app_name} workers in ${var.env}"
  owner_type   = "service-account"
  owner_id     = temporalcloud_service_account.this[0].id
  expiry_time  = var.api_key_expiry
}

# -----------------------------------------------------------------------------
# Secrets Manager — persist the API key token
#
# The temporalcloud_apikey token is only available at creation time.
# Store it in Secrets Manager so workers can retrieve it via ESO/SDK.
# Secret name: temporal/{app_name}-{env}/api-key
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# API Key Expiry Warning
#
# Fires on every plan/apply when the key is within 30 days of expiry.
# Non-blocking (warning, not error) — gives you time to rotate.
# -----------------------------------------------------------------------------

check "api_key_expiry" {
  assert {
    condition = (
      var.api_key_expiry == "" ||
      timecmp(plantimestamp(), timeadd(var.api_key_expiry, "-720h")) < 0
    )
    error_message = "Temporal API key for ${local.namespace_name} expires within 30 days (${var.api_key_expiry}). Rotate it."
  }
}

resource "aws_secretsmanager_secret" "api_key" {
  count = var.create_service_account && var.api_key_expiry != "" && var.store_api_key_in_secrets_manager ? 1 : 0

  name        = "temporal/${local.namespace_name}/api-key"
  description = "Temporal Cloud API key for ${var.app_name} ${var.env} workers"
  kms_key_id  = var.secrets_kms_key_arn

  tags = merge(var.tags, {
    Name      = "temporal/${local.namespace_name}/api-key"
    ManagedBy = "terraform"
  })
}

resource "aws_secretsmanager_secret_version" "api_key" {
  count = var.create_service_account && var.api_key_expiry != "" && var.store_api_key_in_secrets_manager ? 1 : 0

  secret_id     = aws_secretsmanager_secret.api_key[0].id
  secret_string = temporalcloud_apikey.this[0].token
}
