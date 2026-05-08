# =============================================================================
# Unit tests for sg_world_ingress.rego.
# =============================================================================
package main

import rego.v1

# --- Pattern A: inline ingress blocks ----------------------------------------

test_passes_when_inline_ingress_is_vpc_local if {
	test_input := {"resource_changes": [{
		"type": "aws_security_group",
		"address": "aws_security_group.vpce",
		"change": {
			"actions": ["create"],
			"after": {"ingress": [{
				"from_port": 443,
				"to_port": 443,
				"cidr_blocks": ["10.0.0.0/16"],
			}]},
		},
	}]}
	count(deny) == 0 with input as test_input
}

test_passes_when_world_ingress_is_on_443 if {
	test_input := {"resource_changes": [{
		"type": "aws_security_group",
		"address": "aws_security_group.alb",
		"change": {
			"actions": ["create"],
			"after": {"ingress": [{
				"from_port": 443,
				"to_port": 443,
				"cidr_blocks": ["0.0.0.0/0"],
			}]},
		},
	}]}
	count(deny) == 0 with input as test_input
}

test_passes_when_world_ingress_is_on_80 if {
	test_input := {"resource_changes": [{
		"type": "aws_security_group",
		"address": "aws_security_group.alb",
		"change": {
			"actions": ["create"],
			"after": {"ingress": [{
				"from_port": 80,
				"to_port": 80,
				"cidr_blocks": ["0.0.0.0/0"],
			}]},
		},
	}]}
	count(deny) == 0 with input as test_input
}

test_fails_when_inline_ingress_opens_ssh_to_world if {
	test_input := {"resource_changes": [{
		"type": "aws_security_group",
		"address": "aws_security_group.bad",
		"change": {
			"actions": ["create"],
			"after": {"ingress": [{
				"from_port": 22,
				"to_port": 22,
				"cidr_blocks": ["0.0.0.0/0"],
			}]},
		},
	}]}
	some msg in deny with input as test_input
	contains(msg, "port range 22-22")
}

test_fails_when_inline_ingress_opens_a_range if {
	test_input := {"resource_changes": [{
		"type": "aws_security_group",
		"address": "aws_security_group.bad_range",
		"change": {
			"actions": ["create"],
			"after": {"ingress": [{
				"from_port": 80,
				"to_port": 443,
				"cidr_blocks": ["0.0.0.0/0"],
			}]},
		},
	}]}
	some msg in deny with input as test_input
	contains(msg, "port range 80-443")
}

# --- Pattern B: standalone ingress rules -------------------------------------

test_passes_for_standalone_rule_on_443 if {
	test_input := {"resource_changes": [{
		"type": "aws_vpc_security_group_ingress_rule",
		"address": "aws_vpc_security_group_ingress_rule.alb",
		"change": {
			"actions": ["create"],
			"after": {
				"cidr_ipv4": "0.0.0.0/0",
				"from_port": 443,
				"to_port": 443,
			},
		},
	}]}
	count(deny) == 0 with input as test_input
}

test_fails_when_standalone_rule_opens_postgres_to_world if {
	test_input := {"resource_changes": [{
		"type": "aws_vpc_security_group_ingress_rule",
		"address": "aws_vpc_security_group_ingress_rule.bad",
		"change": {
			"actions": ["create"],
			"after": {
				"cidr_ipv4": "0.0.0.0/0",
				"from_port": 5432,
				"to_port": 5432,
			},
		},
	}]}
	some msg in deny with input as test_input
	contains(msg, "port range 5432-5432")
}
