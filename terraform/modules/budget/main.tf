# =============================================================================
# Aegis budget alarm — daily-cost circuit breaker.
#
# This module is the third teardown safety net described in PROJECT.md §9:
#   1. `make eks-down` runs `terraform destroy` and verifies nothing remains.
#   2. Scheduled GitHub Actions teardown (Phase 1 to-do).
#   3. AWS Budget at $5/day → SNS email.
#
# Distinct from the Cost Anomaly Detection that ships with new accounts.
# Anomaly Detection only fires on UNEXPECTED spikes (model-based, default
# >= $100 absolute AND >= 40% delta). A forgotten EKS control plane at
# ~$2.40/day looks "normal" to that model and never trips. This Budget is
# threshold-based — when daily spend crosses $5, you get an email within
# hours regardless of whether AWS thinks the spend is "expected."
#
# Notifications (2 thresholds, both wired to the same SNS topic):
#   - 80% ACTUAL   — early warning at $4
#   - 100% ACTUAL  — the cap is hit at $5
#
# No FORECASTED notification: AWS Budgets only supports FORECASTED on
# MONTHLY+ time units. Daily forecasting isn't statistically meaningful in
# their model, and the API rejects it with InvalidParameterException. If
# you ever want forecast-based alerts, add a second budget at MONTHLY
# granularity (~$40 cap aligned with PROJECT.md §9).
#
# Both notifications publish to ONE SNS topic. Email is the only subscriber
# for now; adding Slack/PagerDuty later is just another
# aws_sns_topic_subscription resource — the budget definition does not
# need to change.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  module_tags = merge(
    { Module = "budget" },
    var.tags,
  )

  # Notification rules, defined as data so the resource block stays short
  # and adding/removing a threshold is a one-line change. DAILY budgets
  # only support notification_type = ACTUAL — see header comment.
  notification_rules = [
    {
      threshold         = 80
      notification_type = "ACTUAL"
    },
    {
      threshold         = 100
      notification_type = "ACTUAL"
    },
  ]
}

# -----------------------------------------------------------------------------
# SNS topic — the fan-out point for all budget alerts.
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "budget" {
  name = "${var.name}-budget-alerts"

  tags = merge(local.module_tags, {
    Name = "${var.name}-budget-alerts"
  })
}

# Topic policy: only the AWS Budgets service in THIS account may publish.
# The aws:SourceAccount condition closes the confused-deputy hole — without
# it, any AWS account's budget service could publish to this topic if it
# guessed the ARN.
data "aws_iam_policy_document" "topic" {
  statement {
    sid    = "AllowBudgetsToPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.budget.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "budget" {
  arn    = aws_sns_topic.budget.arn
  policy = data.aws_iam_policy_document.topic.json
}

# -----------------------------------------------------------------------------
# Email subscription.
#
# AWS sends a confirmation link to var.email after the first apply. Until
# that link is clicked, the subscription stays PendingConfirmation and no
# emails are delivered. This is one-time per email address.
#
# NOTE: aws_sns_topic_subscription cannot be fully managed by Terraform for
# email/email-json protocols — TF can create the subscription request but
# the confirmation must happen out-of-band. After confirmation, the
# subscription appears as PendingConfirmation in TF state until the next
# refresh; that's expected and benign.
# -----------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.budget.arn
  protocol  = "email"
  endpoint  = var.email
}

# -----------------------------------------------------------------------------
# Daily cost budget.
#
# budget_type = COST: actual + forecasted dollar spend (vs. USAGE budgets
#   which track e.g. EC2 hours). COST is what we want for a teardown alarm.
# time_unit   = DAILY: the budget resets every day at 00:00 UTC. PROJECT.md
#   §9 specifies "$5/day" — daily granularity catches a forgotten EKS
#   within hours, not at month-end when the bill arrives.
# limit_unit  = USD: the AWS API requires a string here even though it's a
#   number conceptually. tostring() keeps the variable typed as number for
#   the caller.
# -----------------------------------------------------------------------------

resource "aws_budgets_budget" "daily" {
  name         = "${var.name}-daily-${var.daily_limit_usd}usd"
  budget_type  = "COST"
  limit_amount = tostring(var.daily_limit_usd)
  limit_unit   = "USD"
  time_unit    = "DAILY"

  dynamic "notification" {
    for_each = local.notification_rules

    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.threshold
      threshold_type            = "PERCENTAGE"
      notification_type         = notification.value.notification_type
      subscriber_sns_topic_arns = [aws_sns_topic.budget.arn]
    }
  }

  # Budgets validates the SNS topic policy at create time. Without this
  # depends_on, plan/apply ordering can race and fail with
  # "Cannot publish to SNS topic: not authorized."
  depends_on = [aws_sns_topic_policy.budget]
}
