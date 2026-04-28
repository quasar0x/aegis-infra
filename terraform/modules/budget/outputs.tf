# =============================================================================
# Budget module outputs.
# =============================================================================

output "budget_name" {
  description = "Name of the AWS Budgets resource — useful for cross-referencing in console / CLI."
  value       = aws_budgets_budget.daily.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic carrying budget notifications. Subscribe additional endpoints (Slack, PagerDuty, Lambda) to this ARN — the budget itself never needs to change."
  value       = aws_sns_topic.budget.arn
}
