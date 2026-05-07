# ── Spoke A VPC ───────────────────────────────────────────────────────────────

resource "aws_vpc" "spoke_a" {
  cidr_block           = var.spoke_a_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-a-vpc" })
}

resource "aws_subnet" "spoke_a_az1" {
  vpc_id            = aws_vpc.spoke_a.id
  cidr_block        = var.spoke_a_subnet_az1_cidr
  availability_zone = local.az1
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-a-subnet-az1" })
}

resource "aws_subnet" "spoke_a_az2" {
  vpc_id            = aws_vpc.spoke_a.id
  cidr_block        = var.spoke_a_subnet_az2_cidr
  availability_zone = local.az2
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-a-subnet-az2" })
}

resource "aws_route_table" "spoke_a" {
  vpc_id = aws_vpc.spoke_a.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-a-rt" })
}

resource "aws_route" "spoke_a_default" {
  route_table_id         = aws_route_table.spoke_a.id
  destination_cidr_block = "0.0.0.0/0"
  core_network_arn       = var.core_network_arn
}

resource "aws_route_table_association" "spoke_a_az1" {
  subnet_id      = aws_subnet.spoke_a_az1.id
  route_table_id = aws_route_table.spoke_a.id
}

resource "aws_route_table_association" "spoke_a_az2" {
  subnet_id      = aws_subnet.spoke_a_az2.id
  route_table_id = aws_route_table.spoke_a.id
}

# Test instance in spoke A (AZ1)
resource "aws_instance" "spoke_a_test" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.spoke_a_az1.id
  vpc_security_group_ids = [aws_security_group.spoke_test.id]
  key_name               = var.keypair

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-a-test" })
}

# ── Spoke B VPC ───────────────────────────────────────────────────────────────

resource "aws_vpc" "spoke_b" {
  cidr_block           = var.spoke_b_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-b-vpc" })
}

resource "aws_subnet" "spoke_b_az1" {
  vpc_id            = aws_vpc.spoke_b.id
  cidr_block        = var.spoke_b_subnet_az1_cidr
  availability_zone = local.az1
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-b-subnet-az1" })
}

resource "aws_subnet" "spoke_b_az2" {
  vpc_id            = aws_vpc.spoke_b.id
  cidr_block        = var.spoke_b_subnet_az2_cidr
  availability_zone = local.az2
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-b-subnet-az2" })
}

resource "aws_route_table" "spoke_b" {
  vpc_id = aws_vpc.spoke_b.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-b-rt" })
}

resource "aws_route" "spoke_b_default" {
  route_table_id         = aws_route_table.spoke_b.id
  destination_cidr_block = "0.0.0.0/0"
  core_network_arn       = var.core_network_arn
}

resource "aws_route_table_association" "spoke_b_az1" {
  subnet_id      = aws_subnet.spoke_b_az1.id
  route_table_id = aws_route_table.spoke_b.id
}

resource "aws_route_table_association" "spoke_b_az2" {
  subnet_id      = aws_subnet.spoke_b_az2.id
  route_table_id = aws_route_table.spoke_b.id
}

# Test instance in spoke B (AZ1)
resource "aws_instance" "spoke_b_test" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.spoke_b_az1.id
  vpc_security_group_ids = [aws_security_group.spoke_b_test.id]
  key_name               = var.keypair

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-b-test" })
}

# ── Shared resources ──────────────────────────────────────────────────────────

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "spoke_test" {
  name        = "${local.name_prefix}-spoke-a-test-sg"
  description = "Allow ICMP and SSH for connectivity testing"
  vpc_id      = aws_vpc.spoke_a.id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-test-sg" })
}

resource "aws_security_group" "spoke_b_test" {
  name        = "${local.name_prefix}-spoke-b-test-sg"
  description = "Allow ICMP and SSH for connectivity testing"
  vpc_id      = aws_vpc.spoke_b.id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-spoke-b-test-sg" })
}
