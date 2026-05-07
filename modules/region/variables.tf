variable "cp" { type = string }
variable "env" { type = string }
variable "region_name" {
  description = "Short name for this region used in resource names (east or west)"
  type        = string
}

# ── Network ───────────────────────────────────────────────────────────────────
variable "inspection_vpc_cidr" { type = string }
variable "inspection_public_az1_cidr" { type = string }
variable "inspection_public_az2_cidr" { type = string }
variable "inspection_private_az1_cidr" { type = string }
variable "inspection_private_az2_cidr" { type = string }
variable "inspection_ha_sync_az1_cidr" { type = string }
variable "inspection_ha_sync_az2_cidr" { type = string }

variable "spoke_a_vpc_cidr" { type = string }
variable "spoke_a_subnet_az1_cidr" { type = string }
variable "spoke_a_subnet_az2_cidr" { type = string }
variable "spoke_b_vpc_cidr" { type = string }
variable "spoke_b_subnet_az1_cidr" { type = string }
variable "spoke_b_subnet_az2_cidr" { type = string }

# ── Cloud WAN ─────────────────────────────────────────────────────────────────
variable "core_network_arn" {
  description = "Cloud WAN Core Network ARN — used as route target in VPC route tables"
  type        = string
}

variable "cne_inside_cidr_primary" {
  description = "Inside CIDR for the primary FortiGate Connect Peer"
  type        = string
}

variable "cne_inside_cidr_secondary" {
  description = "Inside CIDR for the secondary FortiGate Connect Peer"
  type        = string
}

variable "cne_bgp_ip_primary" {
  description = "CNE BGP IP for the primary FortiGate (cidrhost(cne_inside_cidr_primary, 1))"
  type        = string
}

variable "cne_bgp_ip_secondary" {
  description = "CNE BGP IP for the secondary FortiGate (cidrhost(cne_inside_cidr_secondary, 1))"
  type        = string
}

variable "cne_asn" {
  description = "BGP ASN of the Cloud WAN Core Network Edge"
  type        = number
}

variable "remote_spoke_a_cidr" {
  description = "Spoke A CIDR from the other region — FortiGate advertises this to Cloud WAN"
  type        = string
}

variable "remote_spoke_b_cidr" {
  description = "Spoke B CIDR from the other region — FortiGate advertises this to Cloud WAN"
  type        = string
}

# ── FortiGate ─────────────────────────────────────────────────────────────────
variable "keypair" { type = string }

variable "fortigate_admin_password" {
  type      = string
  sensitive = true
}

variable "ha_password" {
  type      = string
  sensitive = true
}

variable "ha_group_name" { type = string }
variable "fortigate_instance_type" { type = string }
variable "fortios_version" { type = string }
variable "license_type" { type = string }
variable "fgt_asn" { type = number }
