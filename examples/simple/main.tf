# ---------------------------------------------------------------------------
# Simple Example - Minimal Test Harness
#
# Validates the private distribution bucket collection module with the minimum required inputs
# and secure-by-default configuration:
#   - Single-AZ private subnet for endpoint ENIs
#   - No NAT gateway (endpoint-only egress model)
#   - No Windows test client (validate via AWS CLI / aws s3 cp in CI)
#   - All bucket policy defaults enforced (VPCE-only reads, HTTPS-only)
#
# Harness resource migration path:
#   aws_vpc              -> tf-aws-module_primitive-vpc
#   aws_subnet           -> tf-aws-module_primitive-subnet
#   aws_security_group   -> tf-aws-module_primitive-security_group +
#                           tf-aws-module_primitive-vpc_security_group_ingress_rule +
#                           tf-aws-module_primitive-vpc_security_group_egress_rule
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_role" "current_assumed_role" {
  count = local.resolve_current_iam_role_arn ? 1 : 0
  name  = local.caller_assumed_role_name
}

locals {
  az = data.aws_availability_zones.available.names[0]

  caller_is_assumed_role       = startswith(data.aws_caller_identity.current.arn, "arn:aws:sts::") && strcontains(data.aws_caller_identity.current.arn, ":assumed-role/")
  caller_assumed_role_name     = local.caller_is_assumed_role ? split("/", data.aws_caller_identity.current.arn)[1] : null
  resolve_current_iam_role_arn = length(var.management_principal_arns) == 0 && local.caller_is_assumed_role

  # Example-only fallback: if no management ARNs are provided, trust
  # the current execution principal so local testing and CI can proceed.
  # For STS assumed-role callers (for example SSO sessions), also resolve and
  # include the backing IAM role ARN (with full path) for policy matching.
  effective_management_principal_arns = length(var.management_principal_arns) > 0 ? var.management_principal_arns : distinct(compact(concat(
    [data.aws_caller_identity.current.arn],
    [local.resolve_current_iam_role_arn ? data.aws_iam_role.current_assumed_role[0].arn : null]
  )))
}

# ---------------------------------------------------------------------------
# VPC  (migration target: tf-aws-module_primitive-vpc)
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.name_prefix}-simple-vpc" }
}

resource "aws_default_security_group" "default" {
  vpc_id  = aws_vpc.main.id
  ingress = []
  egress  = []

  tags = { Name = "${var.name_prefix}-simple-default-sg" }
}

# ---------------------------------------------------------------------------
# Single private subnet for VPCE ENIs
# (migration target: tf-aws-module_primitive-subnet)
# ---------------------------------------------------------------------------

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.50.10.0/24"
  availability_zone       = local.az
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-simple-private" }
}

# ---------------------------------------------------------------------------
# VPCE Security Group
# (migration target: tf-aws-module_primitive-security_group +
#                    tf-aws-module_primitive-vpc_security_group_ingress_rule +
#                    tf-aws-module_primitive-vpc_security_group_egress_rule)
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "${var.name_prefix}-simple-vpce-sg"
  description = "S3 interface endpoint - HTTPS inbound from private subnet only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.50.10.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-simple-vpce-sg" }
}

# ---------------------------------------------------------------------------
# Private Distribution Bucket Collection Module
# ---------------------------------------------------------------------------

module "s3_privatelink" {
  source = "../.." # private distribution bucket collection module root

  # Required - networking context
  vpc_id                  = aws_vpc.main.id
  vpce_subnet_ids         = [aws_subnet.private.id]
  vpce_security_group_ids = [aws_security_group.vpce.id]

  # Required - region
  aws_region  = var.aws_region
  name_prefix = var.name_prefix

  management_principal_arns = local.effective_management_principal_arns
  pipeline_role_arns        = var.pipeline_role_arns
  enable_replication        = var.enable_replication

  # All other inputs use secure defaults (see collection module variables.tf)
}
