module "east" {
  source = "./modules/region"
  providers = {
    aws = aws.east
  }

  cp          = var.cp
  env         = var.env
  region_name = "east"

  # Inspection VPC
  inspection_vpc_cidr         = var.east_inspection_vpc_cidr
  inspection_public_az1_cidr  = var.east_inspection_public_az1_cidr
  inspection_public_az2_cidr  = var.east_inspection_public_az2_cidr
  inspection_private_az1_cidr = var.east_inspection_private_az1_cidr
  inspection_private_az2_cidr = var.east_inspection_private_az2_cidr
  inspection_ha_sync_az1_cidr = var.east_inspection_ha_sync_az1_cidr
  inspection_ha_sync_az2_cidr = var.east_inspection_ha_sync_az2_cidr

  # Spoke VPCs
  spoke_a_vpc_cidr         = var.east_spoke_a_vpc_cidr
  spoke_a_subnet_az1_cidr  = var.east_spoke_a_subnet_az1_cidr
  spoke_a_subnet_az2_cidr  = var.east_spoke_a_subnet_az2_cidr
  spoke_b_vpc_cidr         = var.east_spoke_b_vpc_cidr
  spoke_b_subnet_az1_cidr  = var.east_spoke_b_subnet_az1_cidr
  spoke_b_subnet_az2_cidr  = var.east_spoke_b_subnet_az2_cidr

  # Cloud WAN
  core_network_arn           = local.core_network_arn_live
  cne_inside_cidr_primary    = var.cne_inside_cidr_east_primary
  cne_inside_cidr_secondary  = var.cne_inside_cidr_east_secondary
  cne_bgp_ip_primary         = local.cne_bgp_ip_east_primary
  cne_bgp_ip_secondary       = local.cne_bgp_ip_east_secondary
  cne_asn                    = var.cne_asn

  # Remote spoke CIDRs (west region) — advertised to Cloud WAN via BGP
  remote_spoke_a_cidr = var.west_spoke_a_vpc_cidr
  remote_spoke_b_cidr = var.west_spoke_b_vpc_cidr

  # FortiGate
  keypair                  = var.keypair_east
  fortigate_admin_password = var.fortigate_admin_password
  ha_password              = var.ha_password
  ha_group_name            = var.ha_group_name
  fortigate_instance_type  = var.fortigate_instance_type
  fortios_version          = var.fortios_version
  license_type             = var.license_type
  fgt_asn                  = var.fgt_asn
  fortiflex_sn_primary     = var.fortiflex_sn_east_primary
  fortiflex_sn_secondary   = var.fortiflex_sn_east_secondary
}

module "west" {
  source = "./modules/region"
  providers = {
    aws = aws.west
  }

  cp          = var.cp
  env         = var.env
  region_name = "west"

  # Inspection VPC
  inspection_vpc_cidr         = var.west_inspection_vpc_cidr
  inspection_public_az1_cidr  = var.west_inspection_public_az1_cidr
  inspection_public_az2_cidr  = var.west_inspection_public_az2_cidr
  inspection_private_az1_cidr = var.west_inspection_private_az1_cidr
  inspection_private_az2_cidr = var.west_inspection_private_az2_cidr
  inspection_ha_sync_az1_cidr = var.west_inspection_ha_sync_az1_cidr
  inspection_ha_sync_az2_cidr = var.west_inspection_ha_sync_az2_cidr

  # Spoke VPCs
  spoke_a_vpc_cidr         = var.west_spoke_a_vpc_cidr
  spoke_a_subnet_az1_cidr  = var.west_spoke_a_subnet_az1_cidr
  spoke_a_subnet_az2_cidr  = var.west_spoke_a_subnet_az2_cidr
  spoke_b_vpc_cidr         = var.west_spoke_b_vpc_cidr
  spoke_b_subnet_az1_cidr  = var.west_spoke_b_subnet_az1_cidr
  spoke_b_subnet_az2_cidr  = var.west_spoke_b_subnet_az2_cidr

  # Cloud WAN
  core_network_arn           = local.core_network_arn_live
  cne_inside_cidr_primary    = var.cne_inside_cidr_west_primary
  cne_inside_cidr_secondary  = var.cne_inside_cidr_west_secondary
  cne_bgp_ip_primary         = local.cne_bgp_ip_west_primary
  cne_bgp_ip_secondary       = local.cne_bgp_ip_west_secondary
  cne_asn                    = var.cne_asn + 1

  # Remote spoke CIDRs (east region) — advertised to Cloud WAN via BGP
  remote_spoke_a_cidr = var.east_spoke_a_vpc_cidr
  remote_spoke_b_cidr = var.east_spoke_b_vpc_cidr

  # FortiGate
  keypair                  = var.keypair_west
  fortigate_admin_password = var.fortigate_admin_password
  ha_password              = var.ha_password
  ha_group_name            = var.ha_group_name
  fortigate_instance_type  = var.fortigate_instance_type
  fortios_version          = var.fortios_version
  license_type             = var.license_type
  fgt_asn                  = var.fgt_asn
  fortiflex_sn_primary     = var.fortiflex_sn_west_primary
  fortiflex_sn_secondary   = var.fortiflex_sn_west_secondary
}
