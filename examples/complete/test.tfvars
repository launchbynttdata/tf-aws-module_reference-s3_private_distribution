aws_region                     = "us-east-2"
replication_destination_region = "us-west-1"
name_prefix                    = "msix-s3-bucket-complete"

# ---------------------------------------------------------------------------
# Secure baseline - explicit values for all feature flags.
#
# The example module defaults several flags to false for developer convenience
# (no accidental replication bucket creation, etc.). These overrides restore
# the full-feature secure posture that the README describes as the baseline.
# ---------------------------------------------------------------------------
enable_versioning = true
enable_lifecycle  = true
enable_logging    = true
# Baseline uses the module-managed logging bucket so make test covers
# logging bucket create/destroy in the default functional workflow.
use_external_logging_target = false
enable_replication          = true

# Keep make test baseline compatible with an interface-only endpoint stack.
# AWS requires an S3 Gateway endpoint when
# private_dns_only_for_inbound_resolver_endpoint = true.
# The complete example does not create that gateway endpoint.
vpce_private_dns_enabled = true
vpce_dns_options = {
  private_dns_only_for_inbound_resolver_endpoint = false
}

# ---------------------------------------------------------------------------
# Access Control
#
# The module no longer grants a broad same-account bypass.
# Trust is ARN-only. For Terragrunt/CI, pass explicit execution role/user ARNs
# in management_principal_arns.
#
# For additional Terraform/CI principals that run outside VPCE, add explicit
# ARNs to management_principal_arns.
#
# For pipeline roles that need explicit CloudTrail-visible write access,
# add them to pipeline_role_arns. These ARNs are also included in the
# deployer lockout trusted-principal guard to avoid accidental apply-time
# self-lockout, but they are not used in management bypass ARN pattern matching.
#
# Examples:
#   management_principal_arns = [
#     "arn:aws:iam::123456789012:role/terraform-operator",
#   ]
#   pipeline_role_arns = [
#     "arn:aws:iam::123456789012:role/msix-release-pipeline",
#   ]
# ---------------------------------------------------------------------------

tags = {
  Environment = "dev"
  Owner       = "platform"
}
