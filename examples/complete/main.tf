# ---------------------------------------------------------------------------
# Complete Lambda-Based Validation Example
#
# Deploys a VPC with private subnets, S3 PrivateLink endpoint, and a Lambda
# function that validates private access without using S3 IAM credentials.
# The Lambda uses urllib (no boto3) to make raw HTTPS requests via the VPCE,
# relying purely on network path (aws:SourceVpce bucket policy condition).
#
# Networking design:
#   - Lambda runs in private subnets spanning 2 AZs (azs[0..1])
#   - S3 interface endpoint has ENIs in those same 2 subnets
#   - No IGW or NAT - Lambda reaches S3 via the private endpoint only
#
# Test integration:
#   - The Go test invokes the Lambda function synchronously
#   - Lambda returns JSON with 200/403/403 validation results (~5 sec total)
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  disallowed_bucket_name = lower(replace(
    "${var.name_prefix}-disallowed-${random_string.disallowed_bucket_suffix.result}",
    "_", "-"
  ))
}

resource "random_string" "disallowed_bucket_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# VPC and Subnets
# ---------------------------------------------------------------------------

module "vpc" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc?ref=1.0.5"

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_default_security_group" "default" {
  vpc_id  = module.vpc.vpc_id
  ingress = []
  egress  = []
  tags    = { Name = "${var.name_prefix}-default-sg" }
}

module "private_subnets" {
  source   = "git::https://github.com/launchbynttdata/tf-aws-module_primitive-subnet?ref=1.0.5"
  for_each = { for idx, cidr in var.private_subnet_cidrs : tostring(idx) => { cidr = cidr, az = local.azs[idx] } }

  vpc_id                  = module.vpc.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-private-${each.key}" }
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# S3 interface endpoint: accept HTTPS from Lambda subnets.
module "s3_vpce_sg" {
  source      = "git::https://github.com/launchbynttdata/tf-aws-module_primitive-security_group?ref=0.7.3"
  name        = "${var.name_prefix}-s3-vpce-sg"
  description = "S3 interface endpoint - HTTPS inbound from Lambda subnets"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name_prefix}-s3-vpce-sg" }
}

module "s3_vpce_sg_ingress" {
  source   = "git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc_security_group_ingress_rule?ref=0.1.4"
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = module.s3_vpce_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
  description       = "HTTPS from Lambda subnets"
}

# Lambda: outbound HTTPS only. No inbound (Lambda is invoked via AWS API, not network).
module "lambda_sg" {
  source      = "git::https://github.com/launchbynttdata/tf-aws-module_primitive-security_group?ref=0.7.3"
  name        = "${var.name_prefix}-lambda-sg"
  description = "Lambda function - outbound HTTPS to S3 endpoint"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name_prefix}-lambda-sg" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = module.lambda_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
  description       = "HTTPS to S3 endpoint ENIs"
  tags              = { Name = "${var.name_prefix}-lambda-https-out" }
}

# ---------------------------------------------------------------------------
# S3 PrivateLink Collection Module (root module under test)
# ---------------------------------------------------------------------------

module "s3_privatelink" {
  source = "../.."

  vpc_id                  = module.vpc.vpc_id
  vpce_subnet_ids         = [for s in module.private_subnets : s.subnet_id]
  vpce_security_group_ids = [module.s3_vpce_sg.id]

  aws_region  = var.aws_region
  name_prefix = var.name_prefix

  management_principal_arns           = var.management_principal_arns
  pipeline_role_arns                  = var.pipeline_role_arns
  additional_vpce_allowed_bucket_arns = []

  enable_versioning                            = var.enable_versioning
  enable_lifecycle                             = var.enable_lifecycle
  lifecycle_noncurrent_version_expiration_days = var.lifecycle_noncurrent_version_expiration_days
  lifecycle_incomplete_multipart_upload_days   = var.lifecycle_incomplete_multipart_upload_days
  enable_logging                               = var.enable_logging
  logging_target_bucket                        = var.logging_target_bucket
  logging_prefix                               = var.logging_prefix
  enable_replication                           = var.enable_replication
  replication_destination_region               = var.replication_destination_region

  tags = var.tags

  providers = {
    aws.replication = aws.replication
  }
}

# ---------------------------------------------------------------------------
# Sample Artifacts
# ---------------------------------------------------------------------------

resource "aws_s3_object" "sample_appinstaller" {
  bucket       = module.s3_privatelink.s3_bucket_name
  key          = "client/latest/agent-fast.appinstaller"
  content      = "<?xml version=\"1.0\"?><AppInstaller></AppInstaller>"
  content_type = "application/xml"
}

# ---------------------------------------------------------------------------
# Disallowed Bucket (negative test target)
#
# The endpoint policy for the S3 interface endpoint does NOT include this
# bucket in its allowlist. This bucket's own policy DOES allow GetObject so
# that, if the endpoint restriction were absent, the probe would succeed.
# This makes the endpoint policy the sole control under test — a 403 result
# proves the endpoint policy is blocking, not the bucket policy.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "disallowed_target" {
  bucket        = local.disallowed_bucket_name
  force_destroy = true
  tags          = { Name = "${var.name_prefix}-disallowed-bucket" }
}

resource "aws_s3_bucket_public_access_block" "disallowed_target" {
  bucket                  = aws_s3_bucket.disallowed_target.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "disallowed_target" {
  bucket = aws_s3_bucket.disallowed_target.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.disallowed_target.arn, "${aws_s3_bucket.disallowed_target.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        # Bucket policy permits GET so the endpoint policy is the sole control.
        # Without the endpoint restriction this GET would succeed; with it the
        # endpoint policy blocks the request before the bucket policy is reached.
        Sid       = "AllowGetForEndpointPolicyTest"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.disallowed_target.arn}/*"
        Condition = { Bool = { "aws:SecureTransport" = "true" } }
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.disallowed_target]
}

resource "aws_s3_object" "disallowed_probe" {
  bucket       = aws_s3_bucket.disallowed_target.id
  key          = "client/latest/disallowed.txt"
  content      = "This object should be denied by endpoint policy."
  content_type = "text/plain"
}

# ---------------------------------------------------------------------------
# Lambda IAM Execution Role - NO S3 permissions
# Access to S3 is validated by network path only (aws:SourceVpce).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "${var.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = { Name = "${var.name_prefix}-lambda-exec" }
}

# VPC Access + CloudWatch Logs. Explicitly NO S3 policy.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ---------------------------------------------------------------------------
# Lambda Package (zip from local source)
# ---------------------------------------------------------------------------

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_function"
  output_path = "${path.module}/lambda_function.zip"
}

# ---------------------------------------------------------------------------
# Lambda Function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "validation" {
  function_name    = "${var.name_prefix}-s3-probe"
  description      = "S3 PrivateLink access validator - network path only, no IAM"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "index.lambda_handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  timeout          = 30
  memory_size      = 256
  architectures    = ["x86_64"]

  vpc_config {
    subnet_ids         = [for s in module.private_subnets : s.subnet_id]
    security_group_ids = [module.lambda_sg.id]
  }

  environment {
    variables = {
      VPCE_BUCKET_HOST  = module.s3_privatelink.s3_vpce_bucket_host
      ARTIFACT_BUCKET   = module.s3_privatelink.s3_bucket_name
      DISALLOWED_BUCKET = aws_s3_bucket.disallowed_target.id
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    module.s3_privatelink,
  ]
}
