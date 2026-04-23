# =============================================================================
# VPC module outputs.
#
# Every output here is something a downstream module (eks, rds, etc.) will
# need. Keep outputs minimal but complete — hiding useful IDs forces callers
# to re-derive them.
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC — useful for sizing security group rules in other modules."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in AZ-name order."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, in AZ-name order."
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnets_by_az" {
  description = "Map of AZ name to public subnet ID. Useful when downstream modules need to pin resources to specific AZs (e.g., RDS Multi-AZ)."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnets_by_az" {
  description = "Map of AZ name to private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table."
  value       = aws_route_table.private.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group attached to interface VPC endpoints."
  value       = aws_security_group.vpc_endpoints.id
}
