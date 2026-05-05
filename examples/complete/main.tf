# ---------------------------------------------------------------------------
# Complete Example — Full Test Harness
#
# This example exercises every variable of the s3-bucket collection module and
# provides a complete infrastructure harness (VPC, private subnets, security
# groups, Windows client emulator, private SSM endpoints) to validate end-to-end private MSIX
# distribution via S3 PrivateLink.
#
# Harness resource migration path:
#   The bootstrap resources below use direct aws_* resource blocks because the
#   corresponding launchbynttdata primitives are available but not yet wired
#   in. Migration targets are noted per block.
#
#   aws_vpc                       → tf-aws-module_primitive-vpc
#   aws_subnet (public/private)   → tf-aws-module_primitive-subnet
#   aws_security_group (vpce/win) → tf-aws-module_primitive-security_group +
#                                    tf-aws-module_primitive-vpc_security_group_ingress_rule +
#                                    tf-aws-module_primitive-vpc_security_group_egress_rule
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  disallowed_bucket_name = lower(replace("${var.name_prefix}-disallowed-${random_string.disallowed_bucket_suffix.result}", "_", "-"))

  appinstaller_xml = <<-EOT
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller Uri="https://REPLACE_ME/client/latest/agent-fast.appinstaller"
              Version="1.0.0.0"
              xmlns="http://schemas.microsoft.com/appx/appinstaller/2018">
  <MainPackage Name="Contoso.Agent"
               Version="1.0.0.0"
               Uri="https://REPLACE_ME/client/latest/agent.msix"
               Publisher="CN=Contoso"
               ProcessorArchitecture="x64" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="12" />
  </UpdateSettings>
</AppInstaller>
EOT
}

resource "random_string" "disallowed_bucket_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# VPC
# Migration target: tf-aws-module_primitive-vpc
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.name_prefix}-complete-vpc" }
}

resource "aws_default_security_group" "default" {
  vpc_id  = aws_vpc.main.id
  ingress = []
  egress  = []

  tags = { Name = "${var.name_prefix}-complete-default-sg" }
}

# ---------------------------------------------------------------------------
# Subnets (private app + client)
# Migration target: tf-aws-module_primitive-subnet
# ---------------------------------------------------------------------------

resource "aws_subnet" "app_private" {
  for_each = {
    for idx, cidr in var.app_private_subnet_cidrs : idx => {
      cidr = cidr
      az   = local.azs[idx]
    }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-complete-app-private-${each.key}" }
}

resource "aws_subnet" "client" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.client_subnet_cidr
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-complete-client-subnet" }
}

# ---------------------------------------------------------------------------
# Route Table Associations
# No IGW/NAT routes are required. Traffic to S3 and SSM uses interface endpoints
# and remains inside the VPC data plane.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Security Groups
# Migration target: tf-aws-module_primitive-security_group +
#                   tf-aws-module_primitive-vpc_security_group_ingress_rule +
#                   tf-aws-module_primitive-vpc_security_group_egress_rule
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "${var.name_prefix}-complete-vpce-sg"
  description = "S3 interface endpoint - allows HTTPS inbound from private subnets and client subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from client subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.client_subnet_cidr]
  }

  ingress {
    description = "HTTPS from app-private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.app_private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-complete-vpce-sg" }
}

resource "aws_security_group" "windows_client" {
  name        = "${var.name_prefix}-complete-windows-sg"
  description = "Windows emulator - HTTPS egress for package downloads; optional RDP ingress"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.admin_ingress_cidrs
    content {
      description = "Optional RDP admin access"
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-complete-windows-sg" }
}

resource "aws_security_group" "ssm_endpoints" {
  name        = "${var.name_prefix}-complete-ssm-vpce-sg"
  description = "SSM interface endpoints - HTTPS from client and app-private subnets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from client subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.client_subnet_cidr]
  }

  ingress {
    description = "HTTPS from app-private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.app_private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-complete-ssm-vpce-sg" }
}

# ---------------------------------------------------------------------------
# SSM Private Endpoints (Option A)
# Ensures Session Manager works without NAT/IGW/public internet access.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.app_private : s.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]

  tags = { Name = "${var.name_prefix}-complete-ssm-vpce" }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.app_private : s.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]

  tags = { Name = "${var.name_prefix}-complete-ssmmessages-vpce" }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.app_private : s.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]

  tags = { Name = "${var.name_prefix}-complete-ec2messages-vpce" }
}

# ---------------------------------------------------------------------------
# Windows Client Emulator (SSM-managed, no SSH key required)
# This is a test-harness resource. It does not exist in the collection module.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "windows_ssm" {
  name               = "${var.name_prefix}-complete-windows-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.name_prefix}-complete-windows-ssm-role" }
}

resource "aws_iam_role_policy_attachment" "windows_ssm_managed" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "windows_ssm" {
  name = "${var.name_prefix}-complete-windows-ssm-profile"
  role = aws_iam_role.windows_ssm.name
}

resource "aws_instance" "windows_client" {
  ami                         = data.aws_ssm_parameter.windows_ami.value
  instance_type               = var.windows_instance_type
  subnet_id                   = aws_subnet.client.id
  vpc_security_group_ids      = [aws_security_group.windows_client.id]
  iam_instance_profile        = aws_iam_instance_profile.windows_ssm.name
  key_name                    = var.windows_key_name
  associate_public_ip_address = false

  tags = { Name = "${var.name_prefix}-complete-windows-client" }

  depends_on = [
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages
  ]
}

# ---------------------------------------------------------------------------
# S3 PrivateLink Collection Module
# ---------------------------------------------------------------------------

module "s3_privatelink" {
  source = "../.." # the s3-bucket collection module root

  # Networking — provided by harness above
  vpc_id                  = aws_vpc.main.id
  vpce_subnet_ids         = [for s in aws_subnet.app_private : s.id]
  vpce_security_group_ids = [aws_security_group.vpce.id]

  # Region and naming
  aws_region  = var.aws_region
  name_prefix = var.name_prefix

  # Bucket policy principals
  management_principal_arns = var.management_principal_arns
  pipeline_role_arns        = var.pipeline_role_arns

  # Endpoint policy extension
  additional_vpce_allowed_bucket_arns = var.additional_vpce_allowed_bucket_arns

  # Feature toggles
  enable_versioning                            = var.enable_versioning
  enable_lifecycle                             = var.enable_lifecycle
  lifecycle_noncurrent_version_expiration_days = var.lifecycle_noncurrent_version_expiration_days
  lifecycle_incomplete_multipart_upload_days   = var.lifecycle_incomplete_multipart_upload_days

  enable_logging        = var.enable_logging
  logging_target_bucket = var.logging_target_bucket
  logging_prefix        = var.logging_prefix

  enable_replication             = var.enable_replication
  replication_destination_region = var.replication_destination_region

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Sample Artifacts — test-harness only; not managed by the collection module
# These validate the end-to-end S3 access path from the Windows emulator.
# ---------------------------------------------------------------------------

resource "aws_s3_object" "sample_appinstaller" {
  bucket       = module.s3_privatelink.s3_bucket_name
  key          = "client/latest/agent-fast.appinstaller"
  content      = local.appinstaller_xml
  content_type = "application/xml"
}

resource "aws_s3_object" "sample_note" {
  bucket       = module.s3_privatelink.s3_bucket_name
  key          = "client/latest/README.txt"
  content      = "Placeholder artifact for complete-example MSIX distribution test."
  content_type = "text/plain"
}

resource "aws_s3_bucket" "disallowed_target" {
  bucket        = local.disallowed_bucket_name
  force_destroy = true

  tags = { Name = "${var.name_prefix}-complete-disallowed-bucket" }
}

resource "aws_s3_bucket_public_access_block" "disallowed_target" {
  bucket = aws_s3_bucket.disallowed_target.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "disallowed_target" {
  bucket = aws_s3_bucket.disallowed_target.id

  # NOTE: FG_R00100 waiver is documented for this harness bucket because Regula
  # may not fully resolve policy behavior from plan-time unknown values.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.disallowed_target.arn,
          "${aws_s3_bucket.disallowed_target.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "AllowSecureOnlyAccess"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.disallowed_target.arn}/*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
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

locals {
  s3_access_validation_powershell = trimspace(<<-EOT
    $tests = @(
      @{ name = "valid_existing_object"; expected = 200; url = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/agent-fast.appinstaller" },
      # S3 interface endpoint access returns 403 for a missing object in this path,
      # not the public-S3-style 404 many readers would expect.
      @{ name = "invalid_missing_object"; expected = 403; url = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/does-not-exist.appinstaller" },
      @{ name = "disallowed_bucket_object"; expected = 403; url = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${aws_s3_bucket.disallowed_target.id}/client/latest/disallowed.txt" }
    )

    $results = @()
    $failed = $false

    foreach ($test in $tests) {
      $statusCode = -1
      $errorMessage = $null

      try {
        $response = Invoke-WebRequest -Uri $test.url -UseBasicParsing -Method Get -TimeoutSec 30
        $statusCode = [int]$response.StatusCode
      }
      catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
          $statusCode = [int]$_.Exception.Response.StatusCode.value__
        }
        else {
          $statusCode = -1
          $errorMessage = $_.Exception.Message
        }
      }

      $passed = ($statusCode -eq $test.expected)
      if (-not $passed) {
        $failed = $true
      }

      $results += [PSCustomObject]@{
        name     = $test.name
        expected = $test.expected
        actual   = $statusCode
        passed   = $passed
      }
    }

    # Emit only name/expected/actual/passed so the output stays well under
    # SSM GetCommandInvocation's 2500-character StandardOutputContent limit.
    Write-Output "MSIX_S3_PRIVATE_VALIDATION_RESULTS_BEGIN"
    Write-Output ($results | ConvertTo-Json -Compress)
    Write-Output "MSIX_S3_PRIVATE_VALIDATION_RESULTS_END"

    if ($failed) {
      exit 2
    }

    exit 0
  EOT
  )
}

resource "aws_ssm_document" "s3_access_validation" {
  name          = "${var.name_prefix}-s3-private-access-validation"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Validate S3 PrivateLink access behavior (200/403/403) from Windows client; missing object is expected to present as 403 over the S3 interface endpoint path"
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "validateS3PrivateAccess"
        inputs = {
          runCommand = split("\n", local.s3_access_validation_powershell)
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-s3-private-access-validation"
  }
}

resource "aws_ssm_association" "s3_access_validation" {
  count = var.run_ssm_validation_on_apply ? 1 : 0

  name = aws_ssm_document.s3_access_validation.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_client.id]
  }

  association_name = "${var.name_prefix}-s3-private-access-validation"

  depends_on = [
    aws_s3_object.sample_appinstaller,
    aws_s3_object.sample_note,
    aws_s3_object.disallowed_probe,
    aws_s3_bucket_public_access_block.disallowed_target,
    aws_instance.windows_client
  ]
}
