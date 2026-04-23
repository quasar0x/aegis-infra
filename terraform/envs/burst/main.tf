# =============================================================================
# Burst env composition — where modules meet real CIDR values.
#
# This file is the declarative description of the burst-weekend AWS
# environment. Each module block is one feature layer; Phase 1 has just
# the VPC. Later phases add eks, ecr, rds, iam-irsa, karpenter, etc. —
# each a `module "<name>" { source = "../../modules/<name>" }` block.
# =============================================================================

locals {
  # Tags applied to every resource via the provider's default_tags block.
  # `Environment = burst` is the key signal — lets us filter / bill / audit
  # everything created by this env independently of anything else.
  common_tags = {
    Project     = "aegis"
    Environment = "burst"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
# Three AZs in eu-west-2. /20 subnets give ~4,094 IPs each — far more than
# any realistic burst workload needs. Oversizing here is cheap and saves
# future headaches when you add more services.
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  name     = "aegis"
  vpc_cidr = "10.0.0.0/16"

  azs = [
    "eu-west-2a",
    "eu-west-2b",
    "eu-west-2c",
  ]

  public_subnet_cidrs = [
    "10.0.0.0/20",
    "10.0.16.0/20",
    "10.0.32.0/20",
  ]

  private_subnet_cidrs = [
    "10.0.128.0/20",
    "10.0.144.0/20",
    "10.0.160.0/20",
  ]

  tags = local.common_tags
}
