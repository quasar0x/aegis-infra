# =============================================================================
# Outputs — the values other configs need to reference this backend.
#
# The 'burst' env's backend.tf file will hardcode these values (it has to —
# backend config can't be dynamic). But exposing them as outputs keeps the
# connection explicit and lets `terraform output` dump the exact strings to
# paste into backend.tf.
# =============================================================================

output "state_bucket_name" {
  description = "S3 bucket holding Terraform state for all Aegis envs."
  value       = aws_s3_bucket.tf_state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket (useful for future IAM policies)."
  value       = aws_s3_bucket.tf_state.arn
}

output "region" {
  description = "Region the backend lives in."
  value       = var.region
}
