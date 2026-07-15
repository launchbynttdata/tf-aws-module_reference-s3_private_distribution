locals {
  suffix         = random_string.suffix.result
  base_name      = "${var.name_prefix}-${local.suffix}"
  s3_bucket_name = lower(replace("${local.base_name}-artifacts", "_", "-"))

  tags = merge(
    {
      Name              = local.base_name
      Project           = "msix-s3-vpce"
      LogicalOwner      = var.name_prefix
      DeploymentPattern = "option-b-s3-vpce"
      ManagedBy         = "terraform"
    },
    var.tags
  )

  # Lifecycle rules as JSON to ensure consistent normalization across applies.
  # The upstream s3_bucket module's `try(jsondecode(...), ...)` pattern will
  # decode this consistently, preventing state drift on idempotent applies.
  # Note: filter block must include a prefix attribute (even if empty string).
  lifecycle_rules_json = jsonencode(concat(
    var.enable_lifecycle && var.lifecycle_noncurrent_version_expiration_days > 0 ? [{
      id                            = "expire-noncurrent-versions"
      enabled                       = true
      filter                        = { prefix = "" }
      noncurrent_version_expiration = { days = var.lifecycle_noncurrent_version_expiration_days }
    }] : [],
    var.enable_lifecycle && var.lifecycle_incomplete_multipart_upload_days > 0 ? [{
      id                                     = "abort-incomplete-multipart"
      enabled                                = true
      filter                                 = { prefix = "" }
      abort_incomplete_multipart_upload_days = var.lifecycle_incomplete_multipart_upload_days
    }] : []
  ))

  replication_region = var.replication_destination_region != null ? var.replication_destination_region : var.aws_region

  logging_bucket_name_computed = lower(replace("${local.base_name}-logs", "_", "-"))
  # Note: This ARN hardcodes the commercial AWS partition prefix (arn:aws:s3:::).
  # S3 global ARNs omit the region and account segments, but the partition segment
  # differs across AWS partitions: GovCloud uses arn:aws-us-gov:s3::: and China uses
  # arn:aws-cn:s3:::. This module targets commercial AWS only. To support non-commercial
  # partitions, replace with: "arn:${data.aws_partition.current.partition}:s3:::${local.logging_bucket_name_computed}"
  logging_bucket_arn_computed = "arn:aws:s3:::${local.logging_bucket_name_computed}"

  logging_bucket_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          local.logging_bucket_arn_computed,
          "${local.logging_bucket_arn_computed}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid    = "AllowS3LoggingService"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${local.logging_bucket_arn_computed}/*"
        Condition = {
          Bool         = { "aws:SecureTransport" = "true" }
          ArnLike      = { "aws:SourceArn" = module.artifacts_bucket.arn }
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })

  replication_bucket_name_computed = lower(replace("${local.base_name}-replica-${local.replication_region}", "_", "-"))
  replication_bucket_arn_computed  = "arn:aws:s3:::${local.replication_bucket_name_computed}" # see logging_bucket_arn_computed for partition note

  replication_bucket_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          local.replication_bucket_arn_computed,
          "${local.replication_bucket_arn_computed}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid    = "AllowS3ReplicationService"
        Effect = "Allow"
        Principal = {
          AWS = one(aws_iam_role.replication[*].arn)
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${local.replication_bucket_arn_computed}/*"
        Condition = {
          Bool = { "aws:SecureTransport" = "true" }
        }
      }
    ]
  })
}
