# =============================================================================
# Budget module inputs.
# =============================================================================

variable "name" {
  description = "Name prefix applied to the SNS topic and budget. Becomes <name>-budget-alerts and <name>-daily-<N>usd."
  type        = string
}

variable "email" {
  description = "Email address that receives budget notifications. AWS sends a confirmation link on first apply that must be clicked before alerts will arrive."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email))
    error_message = "email must look like an email address."
  }
}

variable "daily_limit_usd" {
  description = "Daily spend cap in whole USD. Two notifications fire at 80% and 100% ACTUAL. (DAILY budgets do not support FORECASTED notifications — AWS API limitation.)"
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags merged onto every taggable resource. Caller-supplied tags win on key conflict."
  type        = map(string)
  default     = {}
}
