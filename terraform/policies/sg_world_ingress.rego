# =============================================================================
# Security groups must not allow 0.0.0.0/0 ingress on non-web ports.
#
# Open-to-the-world ingress on a non-HTTP/HTTPS port is the most common
# AWS misconfiguration: SSH/RDP/postgres/redis left open by accident. This
# policy denies any aws_security_group inline ingress block, or any
# aws_vpc_security_group_ingress_rule (the newer standalone pattern), that
# allows 0.0.0.0/0 on a port other than 80 or 443.
#
# 80 and 443 are explicitly allowed because public load balancers
# legitimately need them. ALB / ingress-nginx security groups will use
# this exception. If you ever need other ports open to the world (rare),
# add a *specific* exception to this policy with a comment explaining why
# — don't widen the allowlist.
#
# Covers both SG patterns:
#   - aws_security_group with inline `ingress {}` blocks (older)
#   - standalone aws_vpc_security_group_ingress_rule resources (newer,
#     preferred — Terraform 5.x recommendation)
# =============================================================================
package main

import rego.v1

# Single-port allowlist for 0.0.0.0/0 ingress.
allowed_world_ports := {80, 443}

# A port range is allowed only if it's a SINGLE port (from == to) AND that
# port is in the allowlist. Range-style rules like 80-443 are rejected
# because they include a lot of unintended ports.
port_range_allowed(from_port, to_port) if {
	from_port == to_port
	from_port in allowed_world_ports
}

# --- Pattern A: inline `ingress {}` blocks on aws_security_group --------------
deny contains msg if {
	some change in input.resource_changes
	change.type == "aws_security_group"
	"create" in change.change.actions

	some ingress in change.change.after.ingress
	"0.0.0.0/0" in ingress.cidr_blocks
	not port_range_allowed(ingress.from_port, ingress.to_port)

	msg := sprintf(
		"Security group %s allows 0.0.0.0/0 ingress on port range %d-%d (only single ports 80 or 443 allowed)",
		[change.address, ingress.from_port, ingress.to_port],
	)
}

# --- Pattern B: standalone aws_vpc_security_group_ingress_rule ----------------
deny contains msg if {
	some change in input.resource_changes
	change.type == "aws_vpc_security_group_ingress_rule"
	"create" in change.change.actions

	change.change.after.cidr_ipv4 == "0.0.0.0/0"
	not port_range_allowed(change.change.after.from_port, change.change.after.to_port)

	msg := sprintf(
		"Ingress rule %s allows 0.0.0.0/0 on port range %d-%d (only single ports 80 or 443 allowed)",
		[change.address, change.change.after.from_port, change.change.after.to_port],
	)
}
