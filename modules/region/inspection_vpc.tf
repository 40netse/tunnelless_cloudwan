locals {
  name_prefix = "${var.cp}-${var.env}-${var.region_name}"
  common_tags = {
    Environment = var.env
    Project     = "tunnelless-cloudwan"
    Terraform   = "true"
  }
}

resource "aws_vpc" "inspection" {
  cidr_block           = var.inspection_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-vpc" })
}

resource "aws_internet_gateway" "inspection" {
  vpc_id = aws_vpc.inspection.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-igw" })
}

# ── Subnets ───────────────────────────────────────────────────────────────────

resource "aws_subnet" "inspection_public_az1" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = var.inspection_public_az1_cidr
  availability_zone = local.az1
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-public-az1" })
}

resource "aws_subnet" "inspection_public_az2" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = var.inspection_public_az2_cidr
  availability_zone = local.az2
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-public-az2" })
}

# Private subnets — FortiGate port2 and Cloud WAN VPC attachment ENIs
resource "aws_subnet" "inspection_private_az1" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = var.inspection_private_az1_cidr
  availability_zone = local.az1
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-private-az1" })
}

resource "aws_subnet" "inspection_private_az2" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = var.inspection_private_az2_cidr
  availability_zone = local.az2
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-private-az2" })
}

# HA sync subnets — FortiGate port3, management EIPs, VPC endpoint
resource "aws_subnet" "inspection_ha_sync_az1" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = var.inspection_ha_sync_az1_cidr
  availability_zone = local.az1
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-ha-sync-az1" })
}

resource "aws_subnet" "inspection_ha_sync_az2" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = var.inspection_ha_sync_az2_cidr
  availability_zone = local.az2
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-ha-sync-az2" })
}

# ── Route tables ──────────────────────────────────────────────────────────────

resource "aws_route_table" "inspection_public" {
  vpc_id = aws_vpc.inspection.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-public-rt" })
}

resource "aws_route" "inspection_public_default" {
  route_table_id         = aws_route_table.inspection_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.inspection.id
}

resource "aws_route_table" "inspection_private" {
  vpc_id = aws_vpc.inspection.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-private-rt" })
}

# Route BGP peering traffic (to CNE inside CIDRs) and all other traffic through Cloud WAN
resource "aws_route" "inspection_private_default_cwan" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  core_network_arn       = var.core_network_arn
}

resource "aws_route_table" "inspection_ha_sync" {
  vpc_id = aws_vpc.inspection.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-inspection-ha-sync-rt" })
}

# HA sync subnets need internet access for management EIPs
resource "aws_route" "inspection_ha_sync_default" {
  route_table_id         = aws_route_table.inspection_ha_sync.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.inspection.id
}

# ── Route table associations ──────────────────────────────────────────────────

resource "aws_route_table_association" "inspection_public_az1" {
  subnet_id      = aws_subnet.inspection_public_az1.id
  route_table_id = aws_route_table.inspection_public.id
}

resource "aws_route_table_association" "inspection_public_az2" {
  subnet_id      = aws_subnet.inspection_public_az2.id
  route_table_id = aws_route_table.inspection_public.id
}

resource "aws_route_table_association" "inspection_private_az1" {
  subnet_id      = aws_subnet.inspection_private_az1.id
  route_table_id = aws_route_table.inspection_private.id
}

resource "aws_route_table_association" "inspection_private_az2" {
  subnet_id      = aws_subnet.inspection_private_az2.id
  route_table_id = aws_route_table.inspection_private.id
}

resource "aws_route_table_association" "inspection_ha_sync_az1" {
  subnet_id      = aws_subnet.inspection_ha_sync_az1.id
  route_table_id = aws_route_table.inspection_ha_sync.id
}

resource "aws_route_table_association" "inspection_ha_sync_az2" {
  subnet_id      = aws_subnet.inspection_ha_sync_az2.id
  route_table_id = aws_route_table.inspection_ha_sync.id
}
