# =============================================================================
# VPC module inputs.
#
# Design principle: the module accepts primitives (CIDRs, AZ names) rather
# than doing clever auto-computation. A reader of the root module should be
# able to tell at a glance which subnet CIDRs go into which AZs.
# =============================================================================

variable "name" {
  description = "Name prefix applied to all resources (used in tags and resource Names)."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC itself. /16 gives ~65k addresses; plenty for a burst weekend."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to span. Length must match public_subnet_cidrs and private_subnet_cidrs."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets — one per AZ in the same order. Hold ALBs and (per PROJECT.md §9) EKS nodes."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets — one per AZ. Used later by RDS (Phase 2+)."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags merged on top of the module's own Name/Tier tags. Use this for Project / Environment / ManagedBy."
  type        = map(string)
  default     = {}
}

variable "create_interface_endpoints" {
  description = <<-EOT
    If true, creates ECR-API/ECR-DKR/STS interface endpoints in the
    private subnets and a security group to fence them. Default false
    because the VPC alone is free, but interface endpoints cost
    ~$0.01/hr per endpoint per AZ — 3 services × 3 AZs ≈ $2/day the
    moment they exist, regardless of whether anything is consuming them.

    Flip to true only when running EKS workloads that need private
    egress to AWS APIs without going via the IGW. The S3 gateway
    endpoint is unconditional and always created (it is free).
  EOT
  type        = bool
  default     = false
}
