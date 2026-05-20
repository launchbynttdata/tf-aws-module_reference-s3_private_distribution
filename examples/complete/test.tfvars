aws_region                     = "us-east-2"
replication_destination_region = "us-west-1"
name_prefix                    = "msix-s3-bucket-complete"

# ---------------------------------------------------------------------------
# Secure baseline — explicit values for all feature flags.
#
# The example module defaults several flags to false for developer convenience
# (no accidental replication bucket creation, etc.). These overrides restore
# the full-feature secure posture that the README describes as the baseline.
# ---------------------------------------------------------------------------
enable_versioning  = true
enable_lifecycle   = true
enable_logging     = true
enable_replication = true

# ---------------------------------------------------------------------------
# Access Control
#
# The identity running `terraform apply` (CI role, SSO session, etc.) is
# automatically exempted from the VPC endpoint restriction via the
# aws:PrincipalAccount condition in the bucket policy — no variable entry
# is needed for the deployer itself.
#
# For pipeline roles that need explicit CloudTrail-visible write access,
# add them to pipeline_role_arns. All other in-account principals already
# have management access via the aws:PrincipalAccount bypass.
#
# Examples:
#   pipeline_role_arns = [
#     "arn:aws:iam::123456789012:role/msix-release-pipeline",
#   ]
# ---------------------------------------------------------------------------

tags = {
  Environment = "dev"
  Owner       = "platform"
}
