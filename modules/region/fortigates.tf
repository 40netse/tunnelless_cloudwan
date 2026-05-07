locals {
  # Primary is deployed in AZ1, secondary in AZ2.
  # IPs are assigned at .10 in each subnet so they're deterministic for the
  # userdata template without needing a second pass.
  primary_port1_ip   = cidrhost(var.inspection_public_az1_cidr, 10)
  primary_port2_ip   = cidrhost(var.inspection_private_az1_cidr, 10)
  primary_port3_ip   = cidrhost(var.inspection_ha_sync_az1_cidr, 10)
  secondary_port1_ip = cidrhost(var.inspection_public_az2_cidr, 10)
  secondary_port2_ip = cidrhost(var.inspection_private_az2_cidr, 10)
  secondary_port3_ip = cidrhost(var.inspection_ha_sync_az2_cidr, 10)
}

# ── Primary FortiGate ENIs ────────────────────────────────────────────────────

resource "aws_network_interface" "primary_port1" {
  subnet_id         = aws_subnet.inspection_public_az1.id
  private_ips       = [local.primary_port1_ip]
  security_groups   = [aws_security_group.fgt_public.id]
  source_dest_check = false
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-primary-port1" })
}

resource "aws_network_interface" "primary_port2" {
  subnet_id         = aws_subnet.inspection_private_az1.id
  private_ips       = [local.primary_port2_ip]
  security_groups   = [aws_security_group.fgt_private.id]
  source_dest_check = false
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-primary-port2" })
}

resource "aws_network_interface" "primary_port3" {
  subnet_id         = aws_subnet.inspection_ha_sync_az1.id
  private_ips       = [local.primary_port3_ip]
  security_groups   = [aws_security_group.fgt_ha_sync.id]
  source_dest_check = false
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-primary-port3" })
}

# ── Secondary FortiGate ENIs ──────────────────────────────────────────────────

resource "aws_network_interface" "secondary_port1" {
  subnet_id         = aws_subnet.inspection_public_az2.id
  private_ips       = [local.secondary_port1_ip]
  security_groups   = [aws_security_group.fgt_public.id]
  source_dest_check = false
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-secondary-port1" })
}

resource "aws_network_interface" "secondary_port2" {
  subnet_id         = aws_subnet.inspection_private_az2.id
  private_ips       = [local.secondary_port2_ip]
  security_groups   = [aws_security_group.fgt_private.id]
  source_dest_check = false
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-secondary-port2" })
}

resource "aws_network_interface" "secondary_port3" {
  subnet_id         = aws_subnet.inspection_ha_sync_az2.id
  private_ips       = [local.secondary_port3_ip]
  security_groups   = [aws_security_group.fgt_ha_sync.id]
  source_dest_check = false
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-secondary-port3" })
}

# ── Primary instance ──────────────────────────────────────────────────────────

resource "aws_instance" "fortigate_primary" {
  ami                  = data.aws_ami.fortigate.id
  instance_type        = var.fortigate_instance_type
  key_name             = var.keypair
  iam_instance_profile = aws_iam_instance_profile.fortigate_ha.name
  user_data            = local.primary_userdata

  network_interface {
    network_interface_id = aws_network_interface.primary_port1.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.primary_port2.id
    device_index         = 1
  }

  network_interface {
    network_interface_id = aws_network_interface.primary_port3.id
    device_index         = 2
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-primary" })
}

# ── Secondary instance ────────────────────────────────────────────────────────

resource "aws_instance" "fortigate_secondary" {
  ami                  = data.aws_ami.fortigate.id
  instance_type        = var.fortigate_instance_type
  key_name             = var.keypair
  iam_instance_profile = aws_iam_instance_profile.fortigate_ha.name
  user_data            = local.secondary_userdata

  network_interface {
    network_interface_id = aws_network_interface.secondary_port1.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.secondary_port2.id
    device_index         = 1
  }

  network_interface {
    network_interface_id = aws_network_interface.secondary_port3.id
    device_index         = 2
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-secondary" })
}
