# =============================================================================
# Aegis VPC — built from primitives so each line is defensible.
#
# Architecture decisions (from PROJECT.md §4, §9):
#   - 3 AZs for Karpenter Spot diversity + EKS control-plane HA.
#   - Public + private subnets per AZ.
#   - NO NAT Gateway (cost). EKS nodes live in PUBLIC subnets with
#     restricted SGs; private AWS API egress goes through VPC endpoints.
#   - Gateway endpoint for S3 (free, wildcard route to AWS); Interface
#     endpoints for ECR-API, ECR-DKR, STS (required for EKS image pulls
#     and IRSA without internet).
#
# Interview framing: "NAT Gateway is $33/month idle — I don't need it
# because I use VPC endpoints for all required AWS APIs. The endpoints
# themselves are $7/month each during bursts only; deleted with the rest
# of the env when the burst ends."
# =============================================================================

locals {
  # Merge the module's own default tags with anything the caller passed in.
  # Caller-supplied tags win on conflict.
  module_tags = merge(
    {
      Module = "vpc"
    },
    var.tags,
  )

  # for_each keys: using AZ names as map keys makes `aws_subnet.public["eu-west-2a"]`
  # a stable address. Adding/removing a subnet later won't force recreation of
  # unrelated subnets the way `count`-indexed resources would.
  public_subnets = {
    for idx, az in var.azs :
    az => {
      cidr_block = var.public_subnet_cidrs[idx]
    }
  }

  private_subnets = {
    for idx, az in var.azs :
    az => {
      cidr_block = var.private_subnet_cidrs[idx]
    }
  }
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
# enable_dns_support + enable_dns_hostnames: both required for EKS's
# kube-dns to work and for AWS private DNS on VPC endpoints to resolve.
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.module_tags, {
    Name = "${var.name}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway — egress path for public subnets.
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.module_tags, {
    Name = "${var.name}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public subnets — one per AZ.
#
# Tag `kubernetes.io/role/elb = 1` tells the AWS Load Balancer Controller
# that these subnets are candidates for public-facing ALB/NLB placement.
# EKS discovers eligible subnets by this tag alone.
# map_public_ip_on_launch = true so EKS worker nodes get a public IP
# automatically (required for image pulls from GHCR/internet during Phase 1).
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(local.module_tags, {
    Name                     = "${var.name}-public-${each.key}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

# -----------------------------------------------------------------------------
# Private subnets — RDS and (future) internal workloads.
#
# Tag `kubernetes.io/role/internal-elb = 1` marks these for internal-only
# load balancers (services that shouldn't be reachable from the internet).
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.key

  tags = merge(local.module_tags, {
    Name                              = "${var.name}-private-${each.key}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# -----------------------------------------------------------------------------
# Route tables + associations.
#
# Public RT has a default route (0.0.0.0/0) to the IGW.
# Private RT has no default route — the ONLY egress from private subnets is
# the VPC endpoints defined below. This is the "no-NAT" design choice.
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.module_tags, {
    Name = "${var.name}-public-rt"
    Tier = "public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.module_tags, {
    Name = "${var.name}-private-rt"
    Tier = "private"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# VPC endpoints.
#
# Gateway endpoints (S3): free, route table entries route S3 traffic directly
# to AWS's backbone without going through the internet. Added to BOTH public
# and private route tables so pods in either tier can pull S3 objects
# (container images from ECR use S3 under the hood).
#
# Interface endpoints (ECR-API, ECR-DKR, STS): create ENIs in each private
# subnet. AWS charges ~$0.01/hour per endpoint per AZ, so 3 endpoints × 3
# AZs × ~48h burst ~= $4 per burst. private_dns_enabled rewrites the AWS
# SDK's default hostname so existing SDKs "just work" — no code changes.
# -----------------------------------------------------------------------------

# Data sources to discover the current region and canonical service names.
data "aws_region" "current" {}

# --- S3 Gateway endpoint (free) ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # Gateway endpoints are attached to route tables. Attach to both so pods
  # in either tier can reach S3 directly via AWS's backbone.
  route_table_ids = concat(
    [aws_route_table.public.id],
    [aws_route_table.private.id],
  )

  tags = merge(local.module_tags, {
    Name = "${var.name}-vpce-s3"
  })
}

# --- Security group for interface endpoints ---
# Interface endpoints need a security group. We allow 443/tcp from inside
# the VPC — enough for every AWS SDK call. Tight enough to be defensible.
#
# Gated by var.create_interface_endpoints (default false). When false, no
# SG is created — the interface endpoints don't exist either, so nothing
# would attach to it. count = 0/1 is the standard pattern for conditional
# single-instance resources.
resource "aws_security_group" "vpc_endpoints" {
  count = var.create_interface_endpoints ? 1 : 0

  name_prefix = "${var.name}-vpce-"
  description = "Allow HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow return traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.module_tags, {
    Name = "${var.name}-vpce-sg"
  })
}

# --- Interface endpoints (ECR API, ECR DKR, STS) ---
# A single aws_vpc_endpoint resource per service, each placed in all private
# subnets. `private_dns_enabled = true` is the magic that makes the AWS SDK
# use the endpoint automatically — no SDK config changes required.
#
# Gated by var.create_interface_endpoints. Default false because each
# endpoint costs ~$0.01/hr per AZ × 3 AZs × 3 services ≈ $2/day, and
# the VPC by itself is free. EKS-related work that actually needs these
# flips the flag at the env level for the duration of the burst.
locals {
  interface_endpoint_services = {
    "ecr-api" = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
    "ecr-dkr" = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
    "sts"     = "com.amazonaws.${data.aws_region.current.name}.sts"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.create_interface_endpoints ? local.interface_endpoint_services : {}

  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  # Place in private subnets across all AZs. Public subnets don't need an
  # endpoint ENI — their default route goes through the IGW anyway, and the
  # endpoint's private DNS name resolves to the private IPs from any
  # subnet in the VPC.
  subnet_ids         = [for s in aws_subnet.private : s.id]
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(local.module_tags, {
    Name = "${var.name}-vpce-${each.key}"
  })
}
