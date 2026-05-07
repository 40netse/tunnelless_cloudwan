resource "aws_iam_role" "fortigate_ha" {
  name = "${local.name_prefix}-fgt-ha-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-ha-role" })
}

resource "aws_iam_policy" "fortigate_ha" {
  name        = "${local.name_prefix}-fgt-ha-policy"
  description = "Allows FortiGate HA cluster to manage EIPs and ENIs for failover"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeAddresses",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeNetworkInterfaceAttribute",
          "ec2:DescribeRouteTables",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:ReplaceRoute",
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-ha-policy" })
}

resource "aws_iam_role_policy_attachment" "fortigate_ha" {
  role       = aws_iam_role.fortigate_ha.name
  policy_arn = aws_iam_policy.fortigate_ha.arn
}

resource "aws_iam_instance_profile" "fortigate_ha" {
  name = "${local.name_prefix}-fgt-ha-profile"
  role = aws_iam_role.fortigate_ha.name

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fgt-ha-profile" })
}
