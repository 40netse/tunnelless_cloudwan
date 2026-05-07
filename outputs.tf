output "core_network_id" {
  value = aws_networkmanager_core_network.main.id
}

output "core_network_arn" {
  value = local.core_network_arn_live
}

# ── us-east-1 ─────────────────────────────────────────────────────────────────
output "east_primary_mgmt_url" {
  description = "HTTPS management URL for east primary FortiGate"
  value       = module.east.primary_mgmt_url
}

output "east_secondary_mgmt_url" {
  description = "HTTPS management URL for east secondary FortiGate"
  value       = module.east.secondary_mgmt_url
}

output "east_primary_port2_ip" {
  description = "East primary FortiGate port2 IP (Cloud WAN peer address)"
  value       = module.east.primary_port2_ip
}

output "east_secondary_port2_ip" {
  description = "East secondary FortiGate port2 IP (Cloud WAN peer address)"
  value       = module.east.secondary_port2_ip
}

output "east_connect_peer_primary_id" {
  value = aws_networkmanager_connect_peer.east_primary.id
}

output "east_connect_peer_secondary_id" {
  value = aws_networkmanager_connect_peer.east_secondary.id
}

# ── us-west-2 ─────────────────────────────────────────────────────────────────
output "west_primary_mgmt_url" {
  description = "HTTPS management URL for west primary FortiGate"
  value       = module.west.primary_mgmt_url
}

output "west_secondary_mgmt_url" {
  description = "HTTPS management URL for west secondary FortiGate"
  value       = module.west.secondary_mgmt_url
}

output "west_primary_port2_ip" {
  description = "West primary FortiGate port2 IP (Cloud WAN peer address)"
  value       = module.west.primary_port2_ip
}

output "west_secondary_port2_ip" {
  description = "West secondary FortiGate port2 IP (Cloud WAN peer address)"
  value       = module.west.secondary_port2_ip
}

output "west_connect_peer_primary_id" {
  value = aws_networkmanager_connect_peer.west_primary.id
}

output "west_connect_peer_secondary_id" {
  value = aws_networkmanager_connect_peer.west_secondary.id
}

# ── BGP reference ─────────────────────────────────────────────────────────────
output "cne_bgp_ips" {
  description = "CNE BGP peer IPs configured on each FortiGate"
  value = {
    east_primary   = local.cne_bgp_ip_east_primary
    east_secondary = local.cne_bgp_ip_east_secondary
    west_primary   = local.cne_bgp_ip_west_primary
    west_secondary = local.cne_bgp_ip_west_secondary
  }
}
