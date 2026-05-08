resource "aws_networkmanager_global_network" "main" {
  description = "${local.name_prefix} tunnelless cloudwan"
  tags        = merge(local.common_tags, { Name = "${local.name_prefix}-global-network" })
}

# Build the policy JSON directly — the Terraform data source (v5 provider) computes
# asn-ranges from per-location ASNs and collapses them, which AWS rejects when
# the range has start == end.  jsonencode gives us full control of the document.
locals {
  core_network_policy_json = jsonencode({
    version = "2021.12"
    "core-network-configuration" = {
      "asn-ranges"         = ["${var.cne_asn}-65534"]
      "vpn-ecmp-support"   = true
      # Global CIDR pool required for Connect Peer CIDR association (NO_ENCAP).
      # Must be RFC 1918, not 169.254.x.x or 100.64.x.x (both restricted by AWS).
      # Must not overlap with any attached VPC CIDRs (10.1-13.x.x).
      "inside-cidr-blocks" = ["10.100.0.0/16"]
      "edge-locations" = [
        { location = "us-east-1", asn = var.cne_asn },
        { location = "us-west-2", asn = var.cne_asn + 1 }
      ]
    }
    segments = [
      {
        name                            = "production"
        "require-attachment-acceptance" = false
        "isolate-attachments"           = false
      }
    ]
    "attachment-policies" = [
      {
        "rule-number" = 100
        conditions    = [{ type = "any" }]
        action = {
          "association-method" = "constant"
          segment              = "production"
        }
      }
    ]
  })
}

resource "aws_networkmanager_core_network" "main" {
  global_network_id = aws_networkmanager_global_network.main.id
  description       = "${local.name_prefix} core network"

  timeouts {
    create = "30m"
    delete = "30m"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-core-network" })
}

# Policy attachment makes the policy "live" — VPC attachments and routes
# cannot be created until this completes and the core network reaches AVAILABLE state.
resource "aws_networkmanager_core_network_policy_attachment" "main" {
  core_network_id = aws_networkmanager_core_network.main.id
  policy_document = local.core_network_policy_json
}
