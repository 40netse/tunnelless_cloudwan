data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az1 = data.aws_availability_zones.available.names[0]
  az2 = data.aws_availability_zones.available.names[1]
}

data "aws_ami" "fortigate" {
  most_recent = true
  owners      = ["679593333241"] # Fortinet Marketplace account

  filter {
    name = "name"
    values = [
      var.license_type == "byol"
      ? "FortiGate-VM64-AWS*(${var.fortios_version}*)*"
      : "FortiGate-VM64-AWSONDEMAND*(${var.fortios_version}*)*"
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
