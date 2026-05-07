# ── us-east-1 VPC attachments ─────────────────────────────────────────────────

resource "aws_networkmanager_vpc_attachment" "east_inspection" {
  core_network_id = local.live_core_network_id
  vpc_arn         = module.east.inspection_vpc_arn
  subnet_arns     = module.east.inspection_private_subnet_arns

  options {
    appliance_mode_support = true
    ipv6_support           = false
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-east-inspection-attachment" })
}

resource "aws_networkmanager_vpc_attachment" "east_spoke_a" {
  core_network_id = local.live_core_network_id
  vpc_arn         = module.east.spoke_a_vpc_arn
  subnet_arns     = module.east.spoke_a_subnet_arns

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-east-spoke-a-attachment" })
}

resource "aws_networkmanager_vpc_attachment" "east_spoke_b" {
  core_network_id = local.live_core_network_id
  vpc_arn         = module.east.spoke_b_vpc_arn
  subnet_arns     = module.east.spoke_b_subnet_arns

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-east-spoke-b-attachment" })
}

# Connect attachment (tunnel-less NO_ENCAP) built on top of the inspection VPC attachment
resource "aws_networkmanager_connect_attachment" "east" {
  core_network_id         = local.live_core_network_id
  transport_attachment_id = aws_networkmanager_vpc_attachment.east_inspection.id
  edge_location           = "us-east-1"

  options {
    protocol = "NO_ENCAP"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-east-connect-attachment" })
}

# Connect Peer for primary FortiGate (us-east-1)
# For NO_ENCAP, inside_cidr_blocks must be omitted — AWS assigns 0.0.0.0/0 automatically.
resource "aws_networkmanager_connect_peer" "east_primary" {
  connect_attachment_id = aws_networkmanager_connect_attachment.east.id
  peer_address          = module.east.primary_port2_ip
  subnet_arn            = module.east.inspection_private_az1_subnet_arn

  bgp_options {
    peer_asn = var.fgt_asn
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-east-fgt-primary-peer" })
}

# Connect Peer for secondary FortiGate (us-east-1)
resource "aws_networkmanager_connect_peer" "east_secondary" {
  connect_attachment_id = aws_networkmanager_connect_attachment.east.id
  peer_address          = module.east.secondary_port2_ip
  subnet_arn            = module.east.inspection_private_az2_subnet_arn

  bgp_options {
    peer_asn = var.fgt_asn
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-east-fgt-secondary-peer" })
}

# ── us-west-2 VPC attachments ─────────────────────────────────────────────────

resource "aws_networkmanager_vpc_attachment" "west_inspection" {
  core_network_id = local.live_core_network_id
  vpc_arn         = module.west.inspection_vpc_arn
  subnet_arns     = module.west.inspection_private_subnet_arns

  options {
    appliance_mode_support = true
    ipv6_support           = false
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-west-inspection-attachment" })
}

resource "aws_networkmanager_vpc_attachment" "west_spoke_a" {
  core_network_id = local.live_core_network_id
  vpc_arn         = module.west.spoke_a_vpc_arn
  subnet_arns     = module.west.spoke_a_subnet_arns

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-west-spoke-a-attachment" })
}

resource "aws_networkmanager_vpc_attachment" "west_spoke_b" {
  core_network_id = local.live_core_network_id
  vpc_arn         = module.west.spoke_b_vpc_arn
  subnet_arns     = module.west.spoke_b_subnet_arns

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-west-spoke-b-attachment" })
}

resource "aws_networkmanager_connect_attachment" "west" {
  core_network_id         = local.live_core_network_id
  transport_attachment_id = aws_networkmanager_vpc_attachment.west_inspection.id
  edge_location           = "us-west-2"

  options {
    protocol = "NO_ENCAP"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-west-connect-attachment" })
}

resource "aws_networkmanager_connect_peer" "west_primary" {
  connect_attachment_id = aws_networkmanager_connect_attachment.west.id
  peer_address          = module.west.primary_port2_ip
  subnet_arn            = module.west.inspection_private_az1_subnet_arn

  bgp_options {
    peer_asn = var.fgt_asn
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-west-fgt-primary-peer" })
}

resource "aws_networkmanager_connect_peer" "west_secondary" {
  connect_attachment_id = aws_networkmanager_connect_attachment.west.id
  peer_address          = module.west.secondary_port2_ip
  subnet_arn            = module.west.inspection_private_az2_subnet_arn

  bgp_options {
    peer_asn = var.fgt_asn
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-west-fgt-secondary-peer" })
}
