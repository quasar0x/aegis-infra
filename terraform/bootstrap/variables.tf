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

variable "budget_email" {
  description = <<-EOT
    Email address that receives daily-budget notifications. Defaults to the
    address the Aegis AWS account was created with. AWS sends a confirmation
    link on first apply — click it before alerts will deliver.
  EOT
  type        = string
  default     = "danielaiops92@gmail.com"
}

variable "daily_budget_usd" {
  description = "Daily spend cap in USD. PROJECT.md §9 specifies $5; bump only with deliberate justification."
  type        = number
  default     = 5
}
