# =============================================================================
# State backend — points at the bucket the bootstrap created.
#
# CRITICAL: the values here cannot be variables or interpolations. Terraform
# reads this block BEFORE evaluating anything else in the config, so all
# fields must be literals. That's why the bucket name is hardcoded with the
# account ID — if you ever needed to change accounts, this string would need
# to be edited by hand.
#
# Locking: we use `use_lockfile = true`, which puts a small ".tflock" object
# in the same S3 key prefix as the state file and uses S3's native conditional
# writes (If-None-Match headers) as the mutex. Added in Terraform 1.10, GA
# since then. Replaces the older DynamoDB-based locking, which required a
# separate table for no benefit.
#
# Interview framing: "S3 now has native strong consistency and conditional
#  writes; DynamoDB locking is a 2018 workaround for a problem that doesn't
#  exist anymore. Using the native mechanism removes a whole piece of
#  infrastructure from the blast radius."
# =============================================================================

terraform {
  backend "s3" {
    bucket       = "aegis-tf-state-023202272343"
    key          = "envs/burst/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    profile      = "aegis"
    use_lockfile = true
  }
}
