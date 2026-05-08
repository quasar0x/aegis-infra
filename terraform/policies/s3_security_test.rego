# =============================================================================
# Unit tests for s3_security.rego.
#
# Inputs are synthetic fragments of `terraform show -json` output — they
# only contain the fields the policy actually reads, which keeps each test
# small enough to read at a glance.
#
# Run via: conftest verify --policy terraform/policies
# =============================================================================
package main

import rego.v1

test_passes_when_bucket_has_all_companions if {
	test_input := {"resource_changes": [
		bucket_change("aws_s3_bucket", "my-bucket"),
		bucket_change("aws_s3_bucket_versioning", "my-bucket"),
		bucket_change("aws_s3_bucket_server_side_encryption_configuration", "my-bucket"),
		bucket_change("aws_s3_bucket_public_access_block", "my-bucket"),
	]}
	count(deny) == 0 with input as test_input
}

test_fails_when_versioning_is_missing if {
	test_input := {"resource_changes": [
		bucket_change("aws_s3_bucket", "my-bucket"),
		bucket_change("aws_s3_bucket_server_side_encryption_configuration", "my-bucket"),
		bucket_change("aws_s3_bucket_public_access_block", "my-bucket"),
	]}
	some msg in deny with input as test_input
	contains(msg, "missing aws_s3_bucket_versioning")
}

test_fails_when_encryption_is_missing if {
	test_input := {"resource_changes": [
		bucket_change("aws_s3_bucket", "my-bucket"),
		bucket_change("aws_s3_bucket_versioning", "my-bucket"),
		bucket_change("aws_s3_bucket_public_access_block", "my-bucket"),
	]}
	some msg in deny with input as test_input
	contains(msg, "missing aws_s3_bucket_server_side_encryption_configuration")
}

test_fails_when_public_access_block_is_missing if {
	test_input := {"resource_changes": [
		bucket_change("aws_s3_bucket", "my-bucket"),
		bucket_change("aws_s3_bucket_versioning", "my-bucket"),
		bucket_change("aws_s3_bucket_server_side_encryption_configuration", "my-bucket"),
	]}
	some msg in deny with input as test_input
	contains(msg, "missing aws_s3_bucket_public_access_block")
}

test_passes_for_plan_with_no_buckets if {
	test_input := {"resource_changes": [{
		"type": "aws_vpc",
		"address": "aws_vpc.main",
		"change": {"actions": ["create"], "after": {"cidr_block": "10.0.0.0/16"}},
	}]}
	count(deny) == 0 with input as test_input
}

# Helper: build a synthetic resource_change matching what `terraform show
# -json` produces. We only set the fields the policy reads.
bucket_change(resource_type, bucket_name) := {
	"type": resource_type,
	"address": sprintf("%s.test", [resource_type]),
	"change": {
		"actions": ["create"],
		"after": {"bucket": bucket_name},
	},
}
