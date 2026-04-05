# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "vpn_connection_id" {
  description = "VPN connection ID"
  value       = aws_vpn_connection.this.id
}

output "customer_gateway_id" {
  description = "Customer gateway ID"
  value       = aws_customer_gateway.this.id
}

output "tunnel1_address" {
  description = "Public IP of VPN tunnel 1 (AWS side)"
  value       = aws_vpn_connection.this.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP of VPN tunnel 2 (AWS side)"
  value       = aws_vpn_connection.this.tunnel2_address
}

output "tunnel1_cgw_inside_address" {
  description = "Inside IP of tunnel 1 (customer gateway side)"
  value       = aws_vpn_connection.this.tunnel1_cgw_inside_address
}

output "tunnel2_cgw_inside_address" {
  description = "Inside IP of tunnel 2 (customer gateway side)"
  value       = aws_vpn_connection.this.tunnel2_cgw_inside_address
}

output "transit_gateway_attachment_id" {
  description = "TGW attachment ID for this VPN connection"
  value       = aws_vpn_connection.this.transit_gateway_attachment_id
}

output "customer_gateway_configuration" {
  description = "VPN tunnel configuration XML (for configuring the remote device)"
  value       = aws_vpn_connection.this.customer_gateway_configuration
  sensitive   = true
}
