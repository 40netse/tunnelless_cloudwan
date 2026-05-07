# ── Naming ────────────────────────────────────────────────────────────────────
variable "cp" {
  description = "Customer prefix — used in all resource names"
  type        = string
  default     = "acme"
}

variable "env" {
  description = "Environment tag"
  type        = string
  default     = "demo"
}

# ── FortiGate credentials ─────────────────────────────────────────────────────
variable "keypair_east" {
  description = "EC2 key pair name in us-east-1"
  type        = string
}

variable "keypair_west" {
  description = "EC2 key pair name in us-west-2"
  type        = string
}

variable "fortigate_admin_password" {
  description = "FortiGate admin password"
  type        = string
  sensitive   = true
}

variable "ha_password" {
  description = "FortiGate HA cluster password"
  type        = string
  sensitive   = true
}

# ── FortiGate instance config ─────────────────────────────────────────────────
variable "fortigate_instance_type" {
  description = "EC2 instance type for FortiGate"
  type        = string
  default     = "c5n.xlarge"
}

variable "fortios_version" {
  description = "FortiOS major.minor version used to select the latest AMI of that branch"
  type        = string
  default     = "7.6"
}

variable "license_type" {
  description = "FortiGate license type: payg or byol"
  type        = string
  default     = "payg"
  validation {
    condition     = contains(["payg", "byol"], var.license_type)
    error_message = "license_type must be payg or byol"
  }
}

variable "ha_group_name" {
  description = "FortiGate HA group name"
  type        = string
  default     = "cloudwan-ha"
}

# ── BGP ───────────────────────────────────────────────────────────────────────
variable "fgt_asn" {
  description = "BGP ASN assigned to all FortiGate instances"
  type        = number
  default     = 65000
}

# Core Network ASN is forced to 64512 via the policy asn-ranges single-value range.
# This makes it deterministic so FortiGate userdata can reference it at plan time.
variable "cne_asn" {
  description = "BGP ASN of the Cloud WAN Core Network Edge (must match asn-ranges in policy)"
  type        = number
  default     = 64512
}

# Inside CIDRs for Connect Peers — /29 from 169.254.0.0/16, one per FortiGate
variable "cne_inside_cidr_east_primary" {
  description = "Inside CIDR for the us-east-1 primary FortiGate Connect Peer"
  type        = string
  default     = "169.254.6.0/29"
}

variable "cne_inside_cidr_east_secondary" {
  description = "Inside CIDR for the us-east-1 secondary FortiGate Connect Peer"
  type        = string
  default     = "169.254.6.8/29"
}

variable "cne_inside_cidr_west_primary" {
  description = "Inside CIDR for the us-west-2 primary FortiGate Connect Peer"
  type        = string
  default     = "169.254.7.0/29"
}

variable "cne_inside_cidr_west_secondary" {
  description = "Inside CIDR for the us-west-2 secondary FortiGate Connect Peer"
  type        = string
  default     = "169.254.7.8/29"
}

# ── us-east-1 network CIDRs ───────────────────────────────────────────────────
variable "east_inspection_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "east_inspection_public_az1_cidr" {
  type    = string
  default = "10.1.1.0/24"
}

variable "east_inspection_public_az2_cidr" {
  type    = string
  default = "10.1.2.0/24"
}

variable "east_inspection_private_az1_cidr" {
  type    = string
  default = "10.1.3.0/24"
}

variable "east_inspection_private_az2_cidr" {
  type    = string
  default = "10.1.4.0/24"
}

variable "east_inspection_ha_sync_az1_cidr" {
  type    = string
  default = "10.1.5.0/24"
}

variable "east_inspection_ha_sync_az2_cidr" {
  type    = string
  default = "10.1.6.0/24"
}

variable "east_spoke_a_vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "east_spoke_a_subnet_az1_cidr" {
  type    = string
  default = "10.2.1.0/24"
}

variable "east_spoke_a_subnet_az2_cidr" {
  type    = string
  default = "10.2.2.0/24"
}

variable "east_spoke_b_vpc_cidr" {
  type    = string
  default = "10.3.0.0/16"
}

variable "east_spoke_b_subnet_az1_cidr" {
  type    = string
  default = "10.3.1.0/24"
}

variable "east_spoke_b_subnet_az2_cidr" {
  type    = string
  default = "10.3.2.0/24"
}

# ── us-west-2 network CIDRs ───────────────────────────────────────────────────
variable "west_inspection_vpc_cidr" {
  type    = string
  default = "10.11.0.0/16"
}

variable "west_inspection_public_az1_cidr" {
  type    = string
  default = "10.11.1.0/24"
}

variable "west_inspection_public_az2_cidr" {
  type    = string
  default = "10.11.2.0/24"
}

variable "west_inspection_private_az1_cidr" {
  type    = string
  default = "10.11.3.0/24"
}

variable "west_inspection_private_az2_cidr" {
  type    = string
  default = "10.11.4.0/24"
}

variable "west_inspection_ha_sync_az1_cidr" {
  type    = string
  default = "10.11.5.0/24"
}

variable "west_inspection_ha_sync_az2_cidr" {
  type    = string
  default = "10.11.6.0/24"
}

variable "west_spoke_a_vpc_cidr" {
  type    = string
  default = "10.12.0.0/16"
}

variable "west_spoke_a_subnet_az1_cidr" {
  type    = string
  default = "10.12.1.0/24"
}

variable "west_spoke_a_subnet_az2_cidr" {
  type    = string
  default = "10.12.2.0/24"
}

variable "west_spoke_b_vpc_cidr" {
  type    = string
  default = "10.13.0.0/16"
}

variable "west_spoke_b_subnet_az1_cidr" {
  type    = string
  default = "10.13.1.0/24"
}

variable "west_spoke_b_subnet_az2_cidr" {
  type    = string
  default = "10.13.2.0/24"
}
