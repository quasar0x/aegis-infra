# =============================================================================
# Aegis Terraform state backend — bootstrap.
#
# The chicken-and-egg problem: Terraform needs an S3 bucket + DynamoDB table
# BEFORE it can use them as a backend. This config creates them using
# *local* state (no backend block). After apply, we'll migrate the main
# env configs to the S3 backend; this bootstrap config itself continues
# to use local state (its tiny state file lives alongside the .tf files
# and is committed… intentionally? no — see .gitignore in repo root).
#
# Interview framing: "Everything the project needs to exist is declarative.
#  The one imperative step — running `terraform apply` on the bootstrap —
#  creates the machinery the rest of the system uses."
# =============================================================================

# -----------------------------------------------------------------------------
# Provider + shared metadata.
# -----------------------------------------------------------------------------

provider "aws" {
  region  = var.region
  profile = var.profile

  # default_tags applies these tags to every resource this provider creates
  # automatically — avoids forgetting on individual resources. This is the
  # "apply project-level tags implicitly, override per-resource only when
  # needed" pattern.
  default_tags {
    tags = local.common_tags
  }
}

# Used to compose globally-unique resource names that include the account ID.
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  state_bucket = "${var.state_bucket_prefix}-${local.account_id}"

  common_tags = {
    Project   = "aegis"
    ManagedBy = "terraform"
    Scope     = "bootstrap"
  }
}

# -----------------------------------------------------------------------------
# S3 bucket — Terraform state storage.
#
# Six resources make one hardened bucket. Each is a *separate* resource
# because AWS split the API surface that way — historically versioning,
# encryption, public access block, etc. were bucket properties, but since
# provider v4+ they're each their own resource. Less magic, easier to audit.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = local.state_bucket

  # Don't let `terraform destroy` nuke the state bucket accidentally. Even a
  # typo on the wrong env could delete every Terraform state file we have.
  # If you genuinely want to destroy this, flip the flag, then destroy, then
  # flip it back.
  lifecycle {
    prevent_destroy = true
  }
}

# Disables ACLs entirely. AWS's modern recommendation — all access control
# goes through the bucket policy. Simpler and more auditable than ACLs.
resource "aws_s3_bucket_ownership_controls" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Versioning: every state write creates a new object version. If a corrupt
# state ever gets written (or someone edits it by hand), we can roll back.
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with AES256 (SSE-S3). Terraform state can contain
# secrets accidentally (resource attributes, outputs). Encryption at rest
# is the baseline — PCI DSS 3.4 / SOC 2 C1.1.
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Belt-and-suspenders: explicitly block any public access, even if a future
# policy mistake tries to allow it. Four flags = all the public-access paths.
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep old state versions for 90 days, then expire. Long enough to roll
# back a mistake; short enough that the bucket doesn't grow forever.
resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    # AWS provider 5.x requires an explicit filter block, even if empty
    # (empty filter = applies to all objects in the bucket).
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Bucket policy: two deny rules — (1) reject unencrypted uploads, (2) reject
# anything over plain HTTP. Defense-in-depth beside the encryption
# configuration and public-access block.
resource "aws_s3_bucket_policy" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.tf_state_bucket_policy.json

  # Apply the policy AFTER the public access block is in place; otherwise
  # AWS may reject the policy if it thinks it could grant public access.
  depends_on = [aws_s3_bucket_public_access_block.tf_state]
}

data "aws_iam_policy_document" "tf_state_bucket_policy" {
  # Deny any PutObject that doesn't use AES256 at-rest encryption.
  # In practice Terraform's S3 backend does set this header, so this rule
  # catches misconfigured clients or someone using the AWS CLI by hand.
  statement {
    sid    = "DenyUnencryptedUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256"]
    }
  }

  # Deny any access that isn't over TLS. Belt and suspenders — AWS endpoints
  # default to HTTPS, but an explicit deny makes the control auditable.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# -----------------------------------------------------------------------------
# No DynamoDB lock table.
#
# Terraform 1.10+ supports S3-native locking via `use_lockfile = true` in the
# backend block (see terraform/envs/burst/backend.tf). S3's conditional-write
# API provides the mutex, eliminating the need for a separate DynamoDB table.
# Simpler, fewer moving parts, one less resource in the blast radius.
# -----------------------------------------------------------------------------
