# ---------------------------------------------------------------------------
# EC2 Windows Validation Example — Manual Use Only
#
# Deploys a single-AZ Windows Server instance alongside the S3 PrivateLink
# module to validate private access via SSM Run Command (PowerShell).
# NOT wired to the Go test suite. See README.md for manual usage instructions.
#
# Networking design:
#   - SSM interface endpoints + Windows instance share local.primary_az (azs[0])
#     to avoid DuplicateSubnetsInSameZone errors on interface endpoints.
#   - App subnets span two AZs for S3 endpoint ENI redundancy.
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
  primary_az = data.aws_availability_zones.available.names[0]
  app_azs    = slice(data.aws_availability_zones.available.names, 0, 2)

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

  disallowed_bucket_name = lower(replace("${var.name_prefix}-disallowed-${random_string.disallowed_bucket_suffix.result}", "_", "-"))

  appinstaller_xml = <<-EOT
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller Uri="https://REPLACE_ME/client/latest/agent-fast.appinstaller"
              Version="1.0.0.0"
              xmlns="http://schemas.microsoft.com/appx/appinstaller/2018">
  <MainPackage Name="Contoso.Agent" Version="1.0.0.0"
               Uri="https://REPLACE_ME/client/latest/agent.msix"
               Publisher="CN=Contoso" ProcessorArchitecture="x64" />
  <UpdateSettings><OnLaunch HoursBetweenUpdateChecks="12" /></UpdateSettings>
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

resource "random_id" "windows_resources_suffix" {
  byte_length = 2
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

module "vpc" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc/aws"
  version = "~> 1.0"

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.name_prefix}-win-vpc" }
}

resource "aws_default_security_group" "default" {
  vpc_id  = module.vpc.vpc_id
  ingress = []
  egress  = []
  tags    = { Name = "${var.name_prefix}-win-default-sg" }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

module "app_private_subnets" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/subnet/aws"
  version = "~> 1.0"

  for_each = {
    for idx, cidr in var.app_private_subnet_cidrs :
    tostring(idx) => { cidr = cidr, az = local.app_azs[idx] }
  }

  vpc_id                  = module.vpc.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-win-app-${each.key}" }
}

module "client_subnet" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/subnet/aws"
  version = "~> 1.0"

  vpc_id                  = module.vpc.vpc_id
  cidr_block              = var.client_subnet_cidr
  availability_zone       = local.primary_az
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-win-client-subnet" }
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

module "vpce_sg" {
  source      = "terraform.registry.launch.nttdata.com/module_primitive/security_group/aws"
  version     = "~> 0.7"
  name        = "${var.name_prefix}-win-vpce-sg"
  description = "S3 interface endpoint - HTTPS inbound"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name_prefix}-win-vpce-sg" }
}

module "vpce_sg_ingress" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version = "~> 0.1"

  for_each = toset(concat([var.client_subnet_cidr], var.app_private_subnet_cidrs))

  security_group_id = module.vpce_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
  description       = "HTTPS from subnets"
}

module "windows_client_sg" {
  source      = "terraform.registry.launch.nttdata.com/module_primitive/security_group/aws"
  version     = "~> 0.7"
  name        = "${var.name_prefix}-win-client-sg"
  description = "Windows emulator security group"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name_prefix}-win-client-sg" }
}

module "windows_client_sg_rdp_ingress" {
  source   = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version  = "~> 0.1"
  for_each = toset(var.admin_ingress_cidrs)

  security_group_id = module.windows_client_sg.id
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = each.value
  description       = "Optional RDP admin access"
}

module "ssm_endpoints_sg" {
  source      = "terraform.registry.launch.nttdata.com/module_primitive/security_group/aws"
  version     = "~> 0.7"
  name        = "${var.name_prefix}-win-ssm-vpce-sg"
  description = "SSM interface endpoints"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name_prefix}-win-ssm-vpce-sg" }
}

module "ssm_endpoints_sg_ingress" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version = "~> 0.1"

  security_group_id = module.ssm_endpoints_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.client_subnet_cidr
  description       = "HTTPS from client subnet"
}

# ---------------------------------------------------------------------------
# SSM Interface Endpoints — single-AZ (client_subnet only)
# Placing all three endpoints in the same subnet as the Windows instance
# avoids DuplicateSubnetsInSameZone and ensures the SSM path is reachable.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [module.client_subnet.subnet_id]
  security_group_ids  = [module.ssm_endpoints_sg.id]
  tags                = { Name = "${var.name_prefix}-win-ssm-vpce" }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [module.client_subnet.subnet_id]
  security_group_ids  = [module.ssm_endpoints_sg.id]
  tags                = { Name = "${var.name_prefix}-win-ssmmessages-vpce" }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [module.client_subnet.subnet_id]
  security_group_ids  = [module.ssm_endpoints_sg.id]
  tags                = { Name = "${var.name_prefix}-win-ec2messages-vpce" }
}

# ---------------------------------------------------------------------------
# Windows Client Instance
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
  name               = "${var.name_prefix}-win-ssm-role-${random_id.windows_resources_suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = { Name = "${var.name_prefix}-win-ssm-role" }
}

resource "aws_iam_role_policy_attachment" "windows_ssm_managed" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "windows_ssm" {
  name = "${var.name_prefix}-win-ssm-profile-${random_id.windows_resources_suffix.hex}"
  role = aws_iam_role.windows_ssm.name
}

resource "aws_instance" "windows_client" {
  ami                         = data.aws_ssm_parameter.windows_ami.value
  instance_type               = var.windows_instance_type
  subnet_id                   = module.client_subnet.subnet_id
  vpc_security_group_ids      = [module.windows_client_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.windows_ssm.name
  key_name                    = var.windows_key_name
  associate_public_ip_address = false
  tags                        = { Name = "${var.name_prefix}-win-client" }

  depends_on = [
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
  ]
}

# ---------------------------------------------------------------------------
# S3 PrivateLink Collection Module
# ---------------------------------------------------------------------------

module "s3_privatelink" {
  source = "../.."

  vpc_id                  = module.vpc.vpc_id
  vpce_subnet_ids         = [for s in module.app_private_subnets : s.subnet_id]
  vpce_security_group_ids = [module.vpce_sg.id]

  aws_region  = var.aws_region
  name_prefix = var.name_prefix

  management_principal_arns           = local.effective_management_principal_arns
  pipeline_role_arns                  = var.pipeline_role_arns
  additional_vpce_allowed_bucket_arns = var.additional_vpce_allowed_bucket_arns

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
}

# ---------------------------------------------------------------------------
# Sample Artifacts
# ---------------------------------------------------------------------------

resource "aws_s3_object" "sample_appinstaller" {
  bucket       = module.s3_privatelink.s3_bucket_name
  key          = "client/latest/agent-fast.appinstaller"
  content      = local.appinstaller_xml
  content_type = "application/xml"
}

resource "aws_s3_bucket" "disallowed_target" {
  bucket        = local.disallowed_bucket_name
  force_destroy = true
  tags          = { Name = "${var.name_prefix}-win-disallowed-bucket" }
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
        Sid       = "AllowSecureOnlyAccess"
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
# SSM Validation Document — invoke manually with send-command
# ---------------------------------------------------------------------------

locals {
  s3_access_validation_powershell = trimspace(<<-EOT
    $tests = @(
      @{ name = "valid_existing_object"; expected = 200; url = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/agent-fast.appinstaller" },
      @{ name = "invalid_missing_object"; expected = 403; url = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/does-not-exist.appinstaller" },
      @{ name = "disallowed_bucket_object"; expected = 403; url = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${aws_s3_bucket.disallowed_target.id}/client/latest/disallowed.txt" }
    )
    $results = @(); $failed = $false
    foreach ($test in $tests) {
      $statusCode = -1
      try {
        $response = Invoke-WebRequest -Uri $test.url -UseBasicParsing -Method Get -TimeoutSec 30
        $statusCode = [int]$response.StatusCode
      } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
          $statusCode = [int]$_.Exception.Response.StatusCode.value__
        }
      }
      $passed = ($statusCode -eq $test.expected)
      if (-not $passed) { $failed = $true }
      $results += [PSCustomObject]@{ name=$test.name; expected=$test.expected; actual=$statusCode; passed=$passed }
    }
    Write-Output "MSIX_S3_PRIVATE_VALIDATION_RESULTS_BEGIN"
    Write-Output ($results | ConvertTo-Json -Compress)
    Write-Output "MSIX_S3_PRIVATE_VALIDATION_RESULTS_END"
    if ($failed) { exit 2 }; exit 0
  EOT
  )
}

resource "aws_ssm_document" "s3_access_validation" {
  name          = "${var.name_prefix}-s3-win-validation-${random_id.windows_resources_suffix.hex}"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Validate S3 PrivateLink access (200/403/403) from Windows client"
    mainSteps = [{
      action = "aws:runPowerShellScript"
      name   = "validateS3PrivateAccess"
      inputs = { runCommand = split("\n", local.s3_access_validation_powershell) }
    }]
  })
  tags = { Name = "${var.name_prefix}-s3-win-validation" }
}
