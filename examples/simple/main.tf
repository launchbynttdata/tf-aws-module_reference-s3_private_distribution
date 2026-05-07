# ---------------------------------------------------------------------------
# Simple Example — Minimal Test Harness
#
# Validates the s3-bucket collection module with the minimum required inputs
# and secure-by-default configuration:
#   - Single-AZ private subnet for endpoint ENIs
#   - No NAT gateway (endpoint-only egress model)
#   - No Windows test client (validate via AWS CLI / aws s3 cp in CI)
#   - All bucket policy defaults enforced (VPCE-only reads, HTTPS-only)
#
# Harness resource migration path:
#   aws_vpc              → tf-aws-module_primitive-vpc
#   aws_subnet           → tf-aws-module_primitive-subnet
#   aws_security_group   → tf-aws-module_primitive-security_group +
#                           tf-aws-module_primitive-vpc_security_group_ingress_rule +
#                           tf-aws-module_primitive-vpc_security_group_egress_rule
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az = data.aws_availability_zones.available.names[0]
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
# S3 PrivateLink Collection Module
# ---------------------------------------------------------------------------

module "s3_privatelink" {
  source = "../.." # the s3-bucket collection module root

  # Required — networking context
  vpc_id                  = aws_vpc.main.id
  vpce_subnet_ids         = [aws_subnet.private.id]
  vpce_security_group_ids = [aws_security_group.vpce.id]

  # Required — region
  aws_region  = var.aws_region
  name_prefix = var.name_prefix

  # All other inputs use secure defaults (see collection module variables.tf)

  providers = {
    aws.replication = aws.replication
  }
}
