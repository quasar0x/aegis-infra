# =============================================================================
# Bootstrap inputs.
#
# Intentionally few knobs. This config is meant to be applied ONCE per
# account, so defaulting to the Aegis account's region/names is fine.
# =============================================================================

variable "region" {
  description = "AWS region where the state bucket and lock table live."
  type        = string
  default     = "eu-west-2"
}

variable "profile" {
  description = <<-EOT
    Named AWS CLI profile used by the provider. Hardcoded-ish by default so
    the only way to run this config is with the aegis credentials — defense
    against accidentally applying with the wrong profile.
  EOT
  type        = string
  default     = "aegis"
}

variable "state_bucket_prefix" {
  description = "Prefix for the state bucket. The full bucket name becomes <prefix>-<account_id>, which guarantees global uniqueness without a random suffix."
  type        = string
  default     = "aegis-tf-state"
}
