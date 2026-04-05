# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "peer_name" {
  description = "Short name for this VPN peer (e.g., slc-dc, azure-hub). Used in resource naming."
  type        = string
}

variable "name_prefix" {
  description = "Naming prefix for resources (e.g., csvc-plat-use1)"
  type        = string
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID to attach the VPN connection to"
  type        = string
}

variable "peer_ip" {
  description = "Public IP address of the remote VPN endpoint"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.peer_ip))
    error_message = "peer_ip must be a valid IPv4 address."
  }
}

variable "bgp_asn" {
  description = "BGP ASN for the remote peer"
  type        = number

  validation {
    condition     = var.bgp_asn >= 1 && var.bgp_asn <= 4294967295
    error_message = "bgp_asn must be a valid ASN (1-4294967295)."
  }
}

variable "tunnel1_psk" {
  description = "Pre-shared key for tunnel 1. Use ephemeral values from Secrets Manager."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "tunnel2_psk" {
  description = "Pre-shared key for tunnel 2. Use ephemeral values from Secrets Manager."
  type        = string
  ephemeral   = true
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "static_routes_only" {
  description = "Use static routes instead of BGP. Set to true for devices that don't support BGP."
  type        = bool
  default     = false
}

variable "static_route_cidrs" {
  description = "List of destination CIDRs for static VPN routes (only used when static_routes_only = true)"
  type        = list(string)
  default     = []
}

variable "tunnel_options" {
  description = "Optional tunnel configuration overrides (inside CIDRs, IKE versions, etc.)"
  type = object({
    tunnel1_inside_cidr = optional(string)
    tunnel2_inside_cidr = optional(string)
  })
  default = {}
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days for VPN tunnel logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
