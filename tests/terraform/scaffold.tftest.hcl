# ---------------------------------------------------------------------------
# Terraform Test Scaffold - Baseline Plan Gates
#
# These tests validate the baseline secure profile and key input validations
# at terraform plan time. They are NOT full apply+destroy cycles.
#
# Run with:
#   terraform test -chdir=examples/complete
# ---------------------------------------------------------------------------

variables {
  # Minimal required variables for plan to succeed.
  # All variables in examples/complete have defaults; these overrides document
  # the intent of the test run and keep names distinct from production values.
  aws_region                     = "us-east-2"
  replication_destination_region = "us-west-1"
  name_prefix                    = "test-s3-plan"
}

# ---------------------------------------------------------------------------
# Baseline secure profile
# ---------------------------------------------------------------------------
run "plan_baseline_secure_profile" {
  command = plan

  variables {
    enable_versioning  = true
    enable_lifecycle   = true
    enable_logging     = true
    enable_replication = true
  }
}

# ---------------------------------------------------------------------------
# VPC endpoint option pass-through profile
# ---------------------------------------------------------------------------
run "plan_vpce_endpoint_options" {
  command = plan

  variables {
    vpce_auto_accept     = true
    vpce_ip_address_type = "dualstack"
    vpce_dns_options = {
      dns_record_ip_type                             = "ipv4"
      private_dns_only_for_inbound_resolver_endpoint = false
    }
  }
}

# ---------------------------------------------------------------------------
# Invalid VPC endpoint IP address type
# ---------------------------------------------------------------------------
run "invalid_vpce_ip_address_type" {
  command = plan

  variables {
    vpce_ip_address_type = "invalid"
  }

  expect_failures = [var.vpce_ip_address_type]
}
