# ── Inspection VPC ────────────────────────────────────────────────────────────
output "inspection_vpc_arn" {
  value = aws_vpc.inspection.arn
}

output "inspection_vpc_id" {
  value = aws_vpc.inspection.id
}

output "inspection_private_subnet_arns" {
  description = "Private subnet ARNs used as the Cloud WAN VPC attachment subnets"
  value       = [aws_subnet.inspection_private_az1.arn, aws_subnet.inspection_private_az2.arn]
}

output "inspection_private_az1_subnet_arn" {
  description = "AZ1 private subnet ARN — subnet_arn for primary Connect Peer (NO_ENCAP)"
  value       = aws_subnet.inspection_private_az1.arn
}

output "inspection_private_az2_subnet_arn" {
  description = "AZ2 private subnet ARN — subnet_arn for secondary Connect Peer (NO_ENCAP)"
  value       = aws_subnet.inspection_private_az2.arn
}

# ── Spoke VPCs ────────────────────────────────────────────────────────────────
output "spoke_a_vpc_arn" {
  value = aws_vpc.spoke_a.arn
}

output "spoke_a_subnet_arns" {
  value = [aws_subnet.spoke_a_az1.arn, aws_subnet.spoke_a_az2.arn]
}

output "spoke_b_vpc_arn" {
  value = aws_vpc.spoke_b.arn
}

output "spoke_b_subnet_arns" {
  value = [aws_subnet.spoke_b_az1.arn, aws_subnet.spoke_b_az2.arn]
}

# ── FortiGate IPs ─────────────────────────────────────────────────────────────
output "primary_port2_ip" {
  description = "Primary FortiGate port2 IP — used as peer_address in Cloud WAN Connect Peer"
  value       = local.primary_port2_ip
}

output "secondary_port2_ip" {
  description = "Secondary FortiGate port2 IP — used as peer_address in Cloud WAN Connect Peer"
  value       = local.secondary_port2_ip
}

# ── Management access ─────────────────────────────────────────────────────────
output "primary_mgmt_ip" {
  value = aws_eip.primary_mgmt.public_ip
}

output "secondary_mgmt_ip" {
  value = aws_eip.secondary_mgmt.public_ip
}

output "primary_mgmt_url" {
  value = "https://${aws_eip.primary_mgmt.public_ip}"
}

output "secondary_mgmt_url" {
  value = "https://${aws_eip.secondary_mgmt.public_ip}"
}

output "cluster_eip" {
  value = aws_eip.cluster.public_ip
}
