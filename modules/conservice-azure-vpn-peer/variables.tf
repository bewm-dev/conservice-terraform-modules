# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "peer_name" {
  description = "Short name for this VPN peer (e.g., azure-hub). Used in resource naming."
  type        = string
}

variable "name_prefix" {
  description = "Naming prefix for resources (e.g., csvc-plat-use1)"
  type        = string
}

variable "resource_group" {
  description = "Azure resource group containing the VPN gateway"
  type        = string
}

variable "location" {
  description = "Azure region of the VPN gateway (e.g., westus)"
  type        = string
}

variable "vpn_gateway_name" {
  description = "Name of the existing Azure Virtual Network Gateway"
  type        = string
}

variable "tunnel1_address" {
  description = "Public IP of AWS VPN tunnel 1 (primary)"
  type        = string
}

variable "tunnel2_address" {
  description = "Public IP of AWS VPN tunnel 2 (backup)"
  type        = string
}

variable "shared_key" {
  description = "IPsec pre-shared key (same key used on AWS side)"
  type        = string
  sensitive   = true
}

variable "local_cidrs" {
  description = "AWS CIDRs to advertise to Azure via Local Network Gateway"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "ipsec_policy" {
  description = "IPsec policy for the VPN connections"
  type = object({
    sa_lifetime      = optional(number, 14400)
    sa_datasize      = optional(number, 102400000)
    ipsec_encryption = optional(string, "AES256")
    ipsec_integrity  = optional(string, "SHA256")
    ike_encryption   = optional(string, "AES256")
    ike_integrity    = optional(string, "SHA256")
    dh_group         = optional(string, "DHGroup14")
    pfs_group        = optional(string, "PFS14")
  })
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
