# -----------------------------------------------------------------------------
# conservice-azure-vpn-peer
#
# Azure side of a Site-to-Site VPN connection to AWS. Creates:
# - Two Local Network Gateways (one per AWS tunnel, for redundancy)
# - Two VPN Connections (primary + backup) on an existing Azure VPN Gateway
#
# Designed for for_each over a map of Azure VPN peers in the caller.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Data Source — Look up the existing Azure VPN Gateway
# -----------------------------------------------------------------------------

data "azurerm_virtual_network_gateway" "this" {
  name                = var.vpn_gateway_name
  resource_group_name = var.resource_group
}

# -----------------------------------------------------------------------------
# Local Network Gateways — Represent each AWS tunnel endpoint in Azure
# -----------------------------------------------------------------------------

resource "azurerm_local_network_gateway" "primary" {
  name                = "${var.name_prefix}-vpn-${var.peer_name}-primary-lng"
  resource_group_name = var.resource_group
  location            = var.location
  gateway_address     = var.tunnel1_address
  address_space       = var.local_cidrs

  tags = merge(var.tags, {
    Tunnel = "primary"
  })
}

resource "azurerm_local_network_gateway" "backup" {
  name                = "${var.name_prefix}-vpn-${var.peer_name}-backup-lng"
  resource_group_name = var.resource_group
  location            = var.location
  gateway_address     = var.tunnel2_address
  address_space       = var.local_cidrs

  tags = merge(var.tags, {
    Tunnel = "backup"
  })
}

# -----------------------------------------------------------------------------
# VPN Connections — IPsec tunnels from Azure VPN Gateway to AWS
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network_gateway_connection" "primary" {
  name                = "${var.name_prefix}-vpn-${var.peer_name}-primary"
  resource_group_name = var.resource_group
  location            = var.location

  type                       = "IPsec"
  virtual_network_gateway_id = data.azurerm_virtual_network_gateway.this.id
  local_network_gateway_id   = azurerm_local_network_gateway.primary.id
  shared_key                 = var.shared_key
  bgp_enabled                = false
  connection_protocol        = "IKEv2"

  ipsec_policy {
    sa_lifetime      = var.ipsec_policy.sa_lifetime
    sa_datasize      = var.ipsec_policy.sa_datasize
    ipsec_encryption = var.ipsec_policy.ipsec_encryption
    ipsec_integrity  = var.ipsec_policy.ipsec_integrity
    ike_encryption   = var.ipsec_policy.ike_encryption
    ike_integrity    = var.ipsec_policy.ike_integrity
    dh_group         = var.ipsec_policy.dh_group
    pfs_group        = var.ipsec_policy.pfs_group
  }

  tags = merge(var.tags, {
    Tunnel = "primary"
  })
}

resource "azurerm_virtual_network_gateway_connection" "backup" {
  name                = "${var.name_prefix}-vpn-${var.peer_name}-backup"
  resource_group_name = var.resource_group
  location            = var.location

  type                       = "IPsec"
  virtual_network_gateway_id = data.azurerm_virtual_network_gateway.this.id
  local_network_gateway_id   = azurerm_local_network_gateway.backup.id
  shared_key                 = var.shared_key
  bgp_enabled                = false
  connection_protocol        = "IKEv2"

  ipsec_policy {
    sa_lifetime      = var.ipsec_policy.sa_lifetime
    sa_datasize      = var.ipsec_policy.sa_datasize
    ipsec_encryption = var.ipsec_policy.ipsec_encryption
    ipsec_integrity  = var.ipsec_policy.ipsec_integrity
    ike_encryption   = var.ipsec_policy.ike_encryption
    ike_integrity    = var.ipsec_policy.ike_integrity
    dh_group         = var.ipsec_policy.dh_group
    pfs_group        = var.ipsec_policy.pfs_group
  }

  tags = merge(var.tags, {
    Tunnel = "backup"
  })
}
