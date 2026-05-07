locals {
  # Pre-compute network/mask pairs for FortiOS "set dst <net> <mask>" syntax
  port1_az1_gw = cidrhost(var.inspection_public_az1_cidr, 1)
  port1_az2_gw = cidrhost(var.inspection_public_az2_cidr, 1)
  port2_az1_gw = cidrhost(var.inspection_private_az1_cidr, 1)
  port2_az2_gw = cidrhost(var.inspection_private_az2_cidr, 1)
  port3_az1_gw = cidrhost(var.inspection_ha_sync_az1_cidr, 1)
  port3_az2_gw = cidrhost(var.inspection_ha_sync_az2_cidr, 1)

  port1_az1_mask = cidrnetmask(var.inspection_public_az1_cidr)
  port1_az2_mask = cidrnetmask(var.inspection_public_az2_cidr)
  port2_az1_mask = cidrnetmask(var.inspection_private_az1_cidr)
  port2_az2_mask = cidrnetmask(var.inspection_private_az2_cidr)
  port3_az1_mask = cidrnetmask(var.inspection_ha_sync_az1_cidr)
  port3_az2_mask = cidrnetmask(var.inspection_ha_sync_az2_cidr)

  spoke_a_net  = cidrhost(var.spoke_a_vpc_cidr, 0)
  spoke_a_mask = cidrnetmask(var.spoke_a_vpc_cidr)
  spoke_b_net  = cidrhost(var.spoke_b_vpc_cidr, 0)
  spoke_b_mask = cidrnetmask(var.spoke_b_vpc_cidr)

  remote_spoke_a_net  = cidrhost(var.remote_spoke_a_cidr, 0)
  remote_spoke_a_mask = cidrnetmask(var.remote_spoke_a_cidr)
  remote_spoke_b_net  = cidrhost(var.remote_spoke_b_cidr, 0)
  remote_spoke_b_mask = cidrnetmask(var.remote_spoke_b_cidr)

  primary_userdata = templatefile("${path.module}/templates/fgt_primary.tpl", {
    hostname      = "${local.name_prefix}-fgt-primary"
    admin_password = var.fortigate_admin_password
    ha_password   = var.ha_password
    ha_group_name = var.ha_group_name
    ha_peer_ip    = local.secondary_port3_ip

    port1_ip   = local.primary_port1_ip
    port1_mask = local.port1_az1_mask
    port1_gw   = local.port1_az1_gw
    port2_ip   = local.primary_port2_ip
    port2_mask = local.port2_az1_mask
    port2_gw   = local.port2_az1_gw
    port3_ip   = local.primary_port3_ip
    port3_mask = local.port3_az1_mask
    port3_gw   = local.port3_az1_gw

    cne_bgp_ip = var.cne_bgp_ip_primary
    cne_asn    = var.cne_asn
    fgt_asn    = var.fgt_asn

    spoke_a_net          = local.spoke_a_net
    spoke_a_mask         = local.spoke_a_mask
    spoke_b_net          = local.spoke_b_net
    spoke_b_mask         = local.spoke_b_mask
    remote_spoke_a_net   = local.remote_spoke_a_net
    remote_spoke_a_mask  = local.remote_spoke_a_mask
    remote_spoke_b_net   = local.remote_spoke_b_net
    remote_spoke_b_mask  = local.remote_spoke_b_mask
  })

  secondary_userdata = templatefile("${path.module}/templates/fgt_secondary.tpl", {
    hostname      = "${local.name_prefix}-fgt-secondary"
    admin_password = var.fortigate_admin_password
    ha_password   = var.ha_password
    ha_group_name = var.ha_group_name
    ha_peer_ip    = local.primary_port3_ip

    port1_ip   = local.secondary_port1_ip
    port1_mask = local.port1_az2_mask
    port1_gw   = local.port1_az2_gw
    port2_ip   = local.secondary_port2_ip
    port2_mask = local.port2_az2_mask
    port2_gw   = local.port2_az2_gw
    port3_ip   = local.secondary_port3_ip
    port3_mask = local.port3_az2_mask
    port3_gw   = local.port3_az2_gw

    cne_bgp_ip = var.cne_bgp_ip_secondary
    cne_asn    = var.cne_asn
    fgt_asn    = var.fgt_asn

    spoke_a_net          = local.spoke_a_net
    spoke_a_mask         = local.spoke_a_mask
    spoke_b_net          = local.spoke_b_net
    spoke_b_mask         = local.spoke_b_mask
    remote_spoke_a_net   = local.remote_spoke_a_net
    remote_spoke_a_mask  = local.remote_spoke_a_mask
    remote_spoke_b_net   = local.remote_spoke_b_net
    remote_spoke_b_mask  = local.remote_spoke_b_mask
  })
}
