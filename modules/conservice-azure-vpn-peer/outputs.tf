# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "primary_connection_id" {
  description = "Azure VPN connection ID (primary tunnel)"
  value       = azurerm_virtual_network_gateway_connection.primary.id
}

output "backup_connection_id" {
  description = "Azure VPN connection ID (backup tunnel)"
  value       = azurerm_virtual_network_gateway_connection.backup.id
}

output "primary_local_network_gateway_id" {
  description = "Azure Local Network Gateway ID (primary)"
  value       = azurerm_local_network_gateway.primary.id
}

output "backup_local_network_gateway_id" {
  description = "Azure Local Network Gateway ID (backup)"
  value       = azurerm_local_network_gateway.backup.id
}
