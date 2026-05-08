# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ---------------------------------------------------------------------------

provider "aws" {
  alias  = "replication"
  region = var.replication_destination_region != null ? var.replication_destination_region : var.aws_region
}

data "aws_caller_identity" "current" {}

resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# S3 Artifact Bucket
# ---------------------------------------------------------------------------

module "artifacts_bucket" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-s3_bucket?ref=1.1.0"

  bucket_name                        = local.s3_bucket_name
  enable_versioning                  = var.enable_versioning
  use_default_server_side_encryption = true
  lifecycle_rule                     = local.lifecycle_rules_json
  block_public_acls                  = true
  ignore_public_acls                 = true
  block_public_policy                = false
  restrict_public_buckets            = false
  # Logging wired below via aws_s3_bucket_logging — collection module logging var not used here
  # because we need conditional target switching (auto-created vs external)
  tags = merge(local.tags, { Name = "${local.base_name}-artifacts" })
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = module.artifacts_bucket.id

  # NOTE: FG_R00100 waiver exists because Regula evaluates plan JSON, and
  # aws_s3_bucket_policy content is often unknown until apply. This policy still
  # enforces HTTPS via DenyInsecureTransport + secure allow conditions.
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.bucket_policy_statements
  })

  depends_on = [module.artifacts_bucket]
}

# ---------------------------------------------------------------------------
# S3 Logging Bucket (optional, auto-created if not provided)
# ---------------------------------------------------------------------------

module "logging_bucket" {
  count  = var.enable_logging && var.logging_target_bucket == null ? 1 : 0
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-s3_bucket?ref=1.1.0"

  bucket_name                        = local.logging_bucket_name_computed
  use_default_server_side_encryption = true
  block_public_acls                  = true
  ignore_public_acls                 = true
  block_public_policy                = true
  restrict_public_buckets            = true
  attach_policy                      = true
  # NOTE: FG_R00100 waiver covers plan-time policy visibility limits in Regula.
  # Runtime behavior still denies insecure transport for this bucket.
  policy = local.logging_bucket_policy_json
  tags   = merge(local.tags, { Name = "${local.base_name}-logs" })
}

resource "aws_s3_bucket_logging" "artifacts" {
  count         = var.enable_logging ? 1 : 0
  bucket        = module.artifacts_bucket.id
  target_bucket = var.logging_target_bucket != null ? var.logging_target_bucket : module.logging_bucket[0].id
  target_prefix = var.logging_prefix

  depends_on = [
    module.logging_bucket
  ]
}

# ---------------------------------------------------------------------------
# S3 Interface VPC Endpoint
# ---------------------------------------------------------------------------

module "s3_interface_vpce" {
  # source = "git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc_endpoint?ref=v1.0.0"
  source = "../tf-aws-module_primitive-vpc_endpoint"

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false
  subnet_ids          = var.vpce_subnet_ids
  security_group_ids  = var.vpce_security_group_ids
  policy              = local.vpce_endpoint_policy_json

  tags = merge(local.tags, { Name = "${local.base_name}-s3-if-vpce" })
}

# ---------------------------------------------------------------------------
# S3 Replication Bucket (optional)
# ---------------------------------------------------------------------------

module "replication_bucket" {
  count  = var.enable_replication ? 1 : 0
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-s3_bucket?ref=1.1.0"

  providers = {
    aws = aws.replication
  }

  bucket_name                        = local.replication_bucket_name_computed
  enable_versioning                  = true
  use_default_server_side_encryption = true
  block_public_acls                  = true
  ignore_public_acls                 = true
  block_public_policy                = true
  restrict_public_buckets            = true
  attach_policy                      = true
  # NOTE: FG_R00100 waiver covers plan-time policy visibility limits in Regula.
  # Runtime behavior still denies insecure transport for this bucket.
  policy = local.replication_bucket_policy_json
  tags   = merge(local.tags, { Name = "${local.base_name}-replica" })
}

resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${local.base_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${local.base_name}-s3-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = module.artifacts_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${module.artifacts_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${module.replication_bucket[0].arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  count      = var.enable_replication ? 1 : 0
  role       = aws_iam_role.replication[0].name
  policy_arn = aws_iam_policy.replication[0].arn
}

resource "aws_s3_bucket_replication_configuration" "artifacts" {
  count  = var.enable_replication ? 1 : 0
  bucket = module.artifacts_bucket.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 1

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = module.replication_bucket[0].arn
      storage_class = "STANDARD"

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }

  depends_on = [module.artifacts_bucket]
}

locals {
  management_principal_arns = distinct(concat(
    [data.aws_caller_identity.current.arn],
    var.pipeline_role_arns,
    var.management_principal_arns
  ))

  # Management principal ARN patterns for S3 bucket policy conditions.
  #
  # Problem:
  #   - IAM role ARNs have format: arn:aws:iam::ACCOUNT:role/ROLE_NAME
  #   - STS assumed-role session ARNs have format: arn:aws:sts::ACCOUNT:assumed-role/ROLE_NAME/SESSION_NAME
  #   - SSO logins (via Okta, Azure AD, etc.) generate STS assumed-role ARNs, not IAM role ARNs
  #   - Exact ARN matching (ArnEquals) fails to match sessions of the same role
  #
  # Solution:
  #   - Use ArnLike wildcard patterns that match both formats
  #   - Convert IAM role ARNs to STS assumed-role patterns with /* suffix
  #   - Preserve STS ARNs and add /* suffix to match any session name
  #
  # Result:
  #   - arn:aws:iam::123456789012:role/admin-role
  #   → arn:aws:sts::123456789012:assumed-role/admin-role/*
  #
  #   - arn:aws:sts::123456789012:assumed-role/admin-role/user@domain.com
  #   → arn:aws:sts::123456789012:assumed-role/admin-role/*
  #
  # Policy conditions using ArnLike will match all principals with these patterns.
  management_principal_arn_patterns = distinct(compact(concat(
    local.management_principal_arns,
    [
      for arn in local.management_principal_arns :
      startswith(arn, "arn:aws:iam::") ? "${replace(replace(arn, ":iam::", ":sts::"), ":role/", ":assumed-role/")}/*" : null
    ],
    [
      for arn in local.management_principal_arns :
      startswith(arn, "arn:aws:sts::") ? "${join("/", slice(split("/", arn), 0, length(split("/", arn)) - 1))}/*" : null
    ],
    [
      for arn in local.management_principal_arns :
      startswith(arn, "arn:aws:sts::") ? replace(replace(join("/", slice(split("/", arn), 0, length(split("/", arn)) - 1)), ":sts::", ":iam::"), ":assumed-role/", ":role/") : null
    ]
  )))

  s3_vpce_wildcard_dns_candidates = [
    for entry in module.s3_interface_vpce.dns_entry : entry.dns_name if startswith(entry.dns_name, "*.")
  ]

  s3_vpce_bucket_host = (
    length([
      for name in local.s3_vpce_wildcard_dns_candidates : name if !strcontains(name, "-${var.aws_region}")
      ]) > 0 ? replace([
      for name in local.s3_vpce_wildcard_dns_candidates : name if !strcontains(name, "-${var.aws_region}")
      ][0], "*.", "bucket.") : (
      length(local.s3_vpce_wildcard_dns_candidates) > 0 ? replace(local.s3_vpce_wildcard_dns_candidates[0], "*.", "bucket.") : "bucket.${module.s3_interface_vpce.id}.s3.${var.aws_region}.vpce.amazonaws.com"
    )
  )

  vpce_allowed_bucket_arns = distinct(concat(
    [module.artifacts_bucket.arn],
    var.additional_vpce_allowed_bucket_arns
  ))

  vpce_allowed_bucket_resources = flatten([
    for bucket_arn in local.vpce_allowed_bucket_arns : [
      bucket_arn,
      "${bucket_arn}/*"
    ]
  ])

  vpce_endpoint_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowExpectedBucketsOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:ListBucket"]
        Resource  = local.vpce_allowed_bucket_resources
      }
    ]
  })

  pipeline_write_statements = [
    for role_arn in var.pipeline_role_arns : {
      Sid    = "AllowPipelineWrite${replace(replace(split("/", role_arn)[length(split("/", role_arn)) - 1], "-", ""), "_", "")}"
      Effect = "Allow"
      Principal = {
        AWS = role_arn
      }
      Action = [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        module.artifacts_bucket.arn,
        "${module.artifacts_bucket.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "true"
        }
      }
    }
  ]

  # Option B (S3 + Interface Endpoint) Bucket Policy Statements
  #
  # Design goals:
  #   - Clients in allowed subnets can read artifacts ONLY via the S3 interface endpoint (PrivateLink)
  #   - Management principals (Terraform, pipelines) can access the bucket directly (not restricted to endpoint)
  #   - All access requires HTTPS (no insecure transport)
  #   - Subnet-level isolation is the primary security boundary (not SourceIp)
  #
  # Why not SourceIp conditions?
  #   - S3 interface endpoints mask the true source IP with the endpoint ENI's IP
  #   - Bucket policy conditions on aws:SourceIp are unreliable with PrivateLink endpoints
  #   - Network routing (security groups, NACLs) provides the actual boundary
  #
  # Policy Statement Breakdown:
  #
  #   1. DenyAccessOutsideVPCEndpoint
  #      - Denies read (GetObject, ListBucket) and write (PutObject, DeleteObject,
  #        DeleteObjectVersion) actions UNLESS source is the interface endpoint
  #      - EXCEPT for principals matching management_principal_arn_patterns (IAM role
  #        and STS assumed-role patterns for management/pipeline principals)
  #      - Uses ArnNotLike on aws:PrincipalArn to restrict only the specific
  #        management principals — not all in-account principals
  #
  #   2. AllowClientReadViaVPCEndpoint
  #      - Permits GetObject when source is the interface endpoint
  #      - No additional conditions (SourceIp, IP range) — endpoint traffic is sufficient
  #      - Clients outside this endpoint are caught by the Deny statement above
  #
  #   3. AllowManagementAccess
  #      - Explicitly allows full access (Get, List, Put, Delete) to management principals
  #      - Not restricted to endpoint — enables Terraform CLI, AWS console, pipeline operations
  #      - Matches both IAM role ARNs and STS assumed-role session ARNs via ArnLike
  #
  option_b_statements = [
    for statement in [
      {
        Sid       = "DenyAccessOutsideVPCEndpoint"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:AbortMultipartUpload",
        ]
        Resource = [
          module.artifacts_bucket.arn,
          "${module.artifacts_bucket.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:SourceVpce" = module.s3_interface_vpce.id
          }
          ArnNotLike = {
            "aws:PrincipalArn" = local.management_principal_arn_patterns
          }
        }
      },
      {
        Sid       = "AllowClientReadViaVPCEndpoint"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${module.artifacts_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceVpce" = module.s3_interface_vpce.id
          }
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      }
      ,
      {
        Sid       = "AllowManagementAccess"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          module.artifacts_bucket.arn,
          "${module.artifacts_bucket.arn}/*"
        ]
        Condition = {
          ArnLike = {
            "aws:PrincipalArn" = local.management_principal_arn_patterns
          }
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      }
    ] : statement
  ]

  bucket_policy_statements = concat(
    [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          module.artifacts_bucket.arn,
          "${module.artifacts_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ],
    local.option_b_statements,
    local.pipeline_write_statements
  )
}
