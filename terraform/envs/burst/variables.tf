# =============================================================================
# Burst env inputs — deliberately minimal.
#
# Every *value* that's specific to the burst env lives in main.tf, not here.
# Variables here are only for things that might reasonably differ between
# users or machines (profile name, region override during testing).
# =============================================================================

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "profile" {
  description = "AWS CLI profile used by the provider."
  type        = string
  default     = "aegis"
}
