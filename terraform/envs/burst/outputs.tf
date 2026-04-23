# =============================================================================
# Burst env outputs.
#
# Re-export the module outputs at env scope so:
#   - `terraform output vpc_id` works directly at env level
#   - Other configs (if any) can read via a terraform_remote_state block
# =============================================================================

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC created for burst."
}

output "vpc_cidr_block" {
  value       = module.vpc.vpc_cidr_block
  description = "CIDR of the VPC."
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "Public subnet IDs, in AZ order."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "Private subnet IDs, in AZ order."
}
