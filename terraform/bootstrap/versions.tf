# =============================================================================
# Version pinning.
#
# Pin Terraform and the AWS provider explicitly. Same discipline as pinning
# Helm chart versions in our Makefile — unpinned versions silently drift and
# break CI weeks later.
#
# The "~> 5.80" means >= 5.80.0, < 6.0.0 (tilde-major). For bootstrap, any
# 5.x provider works because we use only S3/DynamoDB primitives that have
# been stable for years.
# =============================================================================

terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}
