# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

output "namespace_id" {
  description = "Temporal Cloud namespace ID"
  value       = temporalcloud_namespace.this.id
}

output "namespace_name" {
  description = "Temporal Cloud namespace name"
  value       = temporalcloud_namespace.this.name
}

output "grpc_endpoint" {
  description = "gRPC endpoint for connecting workers to this namespace"
  value       = temporalcloud_namespace.this.endpoints.grpc_address
}

output "web_endpoint" {
  description = "Web UI endpoint for this namespace"
  value       = temporalcloud_namespace.this.endpoints.web_address
}

# -----------------------------------------------------------------------------
# Search Attributes
# -----------------------------------------------------------------------------

output "search_attributes" {
  description = "Map of search attribute name to type"
  value       = { for k, v in temporalcloud_namespace_search_attribute.this : k => v.type }
}

# -----------------------------------------------------------------------------
# Service Account
# -----------------------------------------------------------------------------

output "service_account_id" {
  description = "Temporal Cloud service account ID"
  value       = length(temporalcloud_service_account.this) > 0 ? temporalcloud_service_account.this[0].id : ""
}

output "api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Temporal API key"
  value       = length(aws_secretsmanager_secret.api_key) > 0 ? aws_secretsmanager_secret.api_key[0].arn : ""
}

output "api_key_secret_name" {
  description = "Name of the Secrets Manager secret containing the Temporal API key"
  value       = length(aws_secretsmanager_secret.api_key) > 0 ? aws_secretsmanager_secret.api_key[0].name : ""
}

output "api_key_value" {
  description = "Temporal API key token (sensitive — only available at creation time)"
  value       = length(temporalcloud_apikey.this) > 0 ? temporalcloud_apikey.this[0].token : ""
  sensitive   = true
}
