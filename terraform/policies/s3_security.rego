# =============================================================================
# S3 buckets must be hardened by default.
#
# Every aws_s3_bucket in the plan must be paired with three companion
# resources, all referencing the same bucket name:
#   - aws_s3_bucket_versioning                            (PCI 10.5 — audit)
#   - aws_s3_bucket_server_side_encryption_configuration  (PCI 3.4 / SOC2 C1.1)
#   - aws_s3_bucket_public_access_block                   (defense-in-depth)
#
# These rules mirror what bootstrap/main.tf already does — the policy is
# structurally self-validating against our existing code. The point is to
# catch the next bucket someone adds without all three companions, before
# `apply` makes it real.
#
# We deliberately check only EXISTENCE of the companion resource, not the
# attributes inside it (e.g. that versioning_configuration.status =
# "Enabled"). A coarser policy is easier to evolve. Tighter content checks
# can be layered on later if a regression motivates them.
# =============================================================================
package main

import rego.v1

# Set of bucket names being created in this plan.
created_buckets contains name if {
	some change in input.resource_changes
	change.type == "aws_s3_bucket"
	"create" in change.change.actions
	name := change.change.after.bucket
}

# Bucket names covered by a given companion resource type.
companion_buckets(companion_type) := buckets if {
	buckets := {bucket |
		some change in input.resource_changes
		change.type == companion_type
		"create" in change.change.actions
		bucket := change.change.after.bucket
	}
}

deny contains msg if {
	some bucket in created_buckets
	not bucket in companion_buckets("aws_s3_bucket_versioning")
	msg := sprintf("S3 bucket %q is missing aws_s3_bucket_versioning (PCI 10.5)", [bucket])
}

deny contains msg if {
	some bucket in created_buckets
	not bucket in companion_buckets("aws_s3_bucket_server_side_encryption_configuration")
	msg := sprintf("S3 bucket %q is missing aws_s3_bucket_server_side_encryption_configuration (PCI 3.4 / SOC 2 C1.1)", [bucket])
}

deny contains msg if {
	some bucket in created_buckets
	not bucket in companion_buckets("aws_s3_bucket_public_access_block")
	msg := sprintf("S3 bucket %q is missing aws_s3_bucket_public_access_block (defense-in-depth)", [bucket])
}
