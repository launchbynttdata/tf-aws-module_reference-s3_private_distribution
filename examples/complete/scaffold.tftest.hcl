# ---------------------------------------------------------------------------
# Terraform Test Scaffold — Exploratory Profile Plan Gates
#
# These tests validate that each intentionally-relaxed configuration profile
# produces a valid Terraform plan without errors. They are NOT full
# apply+destroy cycles. Security posture assertions for these profiles are
# intentionally omitted — see tests/post_deploy_functional for full validation.
#
# Run with:
#   terraform test -chdir=examples/complete
# ---------------------------------------------------------------------------

variables {
  # Minimal required variables for plan to succeed.
  # All variables in examples/complete have defaults; these overrides document
  # the intent of the test run and keep names distinct from production values.
  aws_region  = "us-east-2"
  name_prefix = "test-s3-plan"
}

# ---------------------------------------------------------------------------
# Logging-disabled profile
# ---------------------------------------------------------------------------
run "plan_logging_disabled" {
  command = plan

  variables {
    enable_logging = false
  }
}

# ---------------------------------------------------------------------------
# Replication-disabled profile
# ---------------------------------------------------------------------------
run "plan_replication_disabled" {
  command = plan

  variables {
    enable_replication = false
  }
}

# ---------------------------------------------------------------------------
# Lifecycle-disabled profile
# ---------------------------------------------------------------------------
run "plan_lifecycle_disabled" {
  command = plan

  variables {
    enable_lifecycle = false
  }
}

# ---------------------------------------------------------------------------
# Versioning-disabled profile
# ---------------------------------------------------------------------------
run "plan_versioning_disabled" {
  command = plan

  variables {
    enable_versioning = false
  }
}
