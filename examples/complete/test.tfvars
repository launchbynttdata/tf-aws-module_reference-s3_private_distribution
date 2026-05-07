aws_region  = "us-east-2"
name_prefix = "msix-s3-bucket-complete"

# ---------------------------------------------------------------------------
# Access Control
#
# The identity running `terraform apply` (CI role, SSO session, etc.) is
# automatically included as a management principal and exempted from the
# VPC endpoint restriction — no entry needed here for the deployer itself.
#
# For real deployments, add ARNs for any principals that need direct S3
# access outside the VPC endpoint path (console users, break-glass roles,
# audit tooling, etc.).  Pipeline roles that write artifacts to the bucket
# should go in pipeline_role_arns instead.
#
# Examples:
#   management_principal_arns = [
#     "arn:aws:iam::123456789012:role/platform-admin",
#     "arn:aws:iam::123456789012:role/s3-console-access",
#   ]
#   pipeline_role_arns = [
#     "arn:aws:iam::123456789012:role/msix-release-pipeline",
#   ]
# ---------------------------------------------------------------------------

tags = {
  Environment = "dev"
  Owner       = "platform"
}
