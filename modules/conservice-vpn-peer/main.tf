# -----------------------------------------------------------------------------
# conservice-vpn-peer
#
# A single site-to-site VPN peer attached to a Transit Gateway.
# Designed for for_each over a map of peers in the caller.
#
# Features:
# - TGW-based (not VGW) — multi-VPC hub routing
# - BGP by default, static routes optional
# - PSKs from Secrets Manager via ephemeral (never in state)
# - Per-tunnel CloudWatch logging
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Customer Gateway
# -----------------------------------------------------------------------------

resource "aws_customer_gateway" "this" {
  bgp_asn    = var.bgp_asn
  ip_address = var.peer_ip
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cgw-${var.peer_name}"
  })
}

# -----------------------------------------------------------------------------
# VPN Connection (TGW-attached)
# -----------------------------------------------------------------------------

resource "aws_vpn_connection" "this" {
  customer_gateway_id = aws_customer_gateway.this.id
  transit_gateway_id  = var.transit_gateway_id
  type                = "ipsec.1"
  static_routes_only  = var.static_routes_only

  # Tunnel config — sensible defaults, override via var.tunnel_options
  tunnel1_inside_cidr   = try(var.tunnel_options.tunnel1_inside_cidr, null)
  tunnel2_inside_cidr   = try(var.tunnel_options.tunnel2_inside_cidr, null)
  tunnel1_preshared_key = var.tunnel1_psk
  tunnel2_preshared_key = var.tunnel2_psk

  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.tunnel1.arn
      log_output_format = "json"
    }
  }

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.tunnel2.arn
      log_output_format = "json"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpn-${var.peer_name}"
  })
}

# -----------------------------------------------------------------------------
# Static Routes (only when static_routes_only = true)
# -----------------------------------------------------------------------------

resource "aws_vpn_connection_route" "this" {
  for_each = var.static_routes_only ? toset(var.static_route_cidrs) : toset([])

  vpn_connection_id      = aws_vpn_connection.this.id
  destination_cidr_block = each.value
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups — Per-Tunnel
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "tunnel1" {
  name              = "/vpn/${var.name_prefix}-${var.peer_name}/tunnel1"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "tunnel2" {
  name              = "/vpn/${var.name_prefix}-${var.peer_name}/tunnel2"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
