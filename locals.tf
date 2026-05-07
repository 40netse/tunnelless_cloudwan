locals {
  common_tags = {
    Environment = var.env
    Project     = "tunnelless-cloudwan"
    Terraform   = "true"
  }

  name_prefix = "${var.cp}-${var.env}"

  # For NO_ENCAP Connect, the CNE BGP IP is the first IP of the inspection private
  # subnet (the AWS VPC router address in that subnet).  No tunnel inside CIDRs exist.
  cne_bgp_ip_east_primary   = cidrhost(var.east_inspection_private_az1_cidr, 1)
  cne_bgp_ip_east_secondary = cidrhost(var.east_inspection_private_az2_cidr, 1)
  cne_bgp_ip_west_primary   = cidrhost(var.west_inspection_private_az1_cidr, 1)
  cne_bgp_ip_west_secondary = cidrhost(var.west_inspection_private_az2_cidr, 1)

  # Both of these derive from the policy attachment so that any resource
  # referencing them implicitly waits for the policy to be live before attempting
  # to create attachments or routes.
  live_core_network_id  = aws_networkmanager_core_network_policy_attachment.main.core_network_id
  core_network_arn_live = "arn:aws:networkmanager::${split(":", aws_networkmanager_core_network.main.arn)[4]}:core-network/${aws_networkmanager_core_network_policy_attachment.main.core_network_id}"
}
