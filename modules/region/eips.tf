# Cluster EIP — moves to the active FortiGate on failover
resource "aws_eip" "cluster" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-cluster-eip" })
}

resource "aws_eip_association" "cluster" {
  network_interface_id = aws_network_interface.primary_port1.id
  allocation_id        = aws_eip.cluster.id
}

# Individual management EIPs — one per FortiGate, stay pinned regardless of HA state
resource "aws_eip" "primary_mgmt" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-primary-mgmt-eip" })
}

resource "aws_eip_association" "primary_mgmt" {
  network_interface_id = aws_network_interface.primary_port3.id
  allocation_id        = aws_eip.primary_mgmt.id
}

resource "aws_eip" "secondary_mgmt" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-secondary-mgmt-eip" })
}

resource "aws_eip_association" "secondary_mgmt" {
  network_interface_id = aws_network_interface.secondary_port3.id
  allocation_id        = aws_eip.secondary_mgmt.id
}
