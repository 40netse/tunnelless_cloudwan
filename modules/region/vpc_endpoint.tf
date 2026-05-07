resource "aws_security_group" "vpc_endpoint" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "Allow HTTPS from inspection VPC to EC2 API endpoint"
  vpc_id      = aws_vpc.inspection.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.inspection_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-sg" })
}

# Private EC2 API endpoint so FortiGate HA failover works without internet access
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.inspection.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.inspection_ha_sync_az1.id, aws_subnet.inspection_ha_sync_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-vpce" })
}
