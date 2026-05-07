resource "aws_security_group" "fgt_public" {
  name        = "${local.name_prefix}-fgt-public-sg"
  description = "FortiGate port1 - allow all (FortiGate enforces policy)"
  vpc_id      = aws_vpc.inspection.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-public-sg" })
}

resource "aws_security_group" "fgt_private" {
  name        = "${local.name_prefix}-fgt-private-sg"
  description = "FortiGate port2 - allow all from inspection VPC and Cloud WAN"
  vpc_id      = aws_vpc.inspection.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-private-sg" })
}

resource "aws_security_group" "fgt_ha_sync" {
  name        = "${local.name_prefix}-fgt-ha-sync-sg"
  description = "FortiGate port3 - HA heartbeat, management, AWS API"
  vpc_id      = aws_vpc.inspection.id

  # HA heartbeat
  ingress {
    from_port   = 703
    to_port     = 703
    protocol    = "udp"
    cidr_blocks = [var.inspection_vpc_cidr]
  }

  # HA sync
  ingress {
    from_port   = 702
    to_port     = 702
    protocol    = "tcp"
    cidr_blocks = [var.inspection_vpc_cidr]
  }

  # HTTPS management
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-ha-sync-sg" })
}
