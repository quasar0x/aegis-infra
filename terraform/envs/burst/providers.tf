# =============================================================================
# Provider configuration for the 'burst' environment.
#
# Named profile is hardcoded — this env's resources must only ever be
# managed by the aegis-admin credentials. No ambiguity about whose
# account this applies to.
# =============================================================================

provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = local.common_tags
  }
}
