aws_region                     = "us-east-2"
replication_destination_region = "us-west-2"
name_prefix                    = "msix-s3-alt-region"

# Secure baseline — same feature set as test.tfvars, only the replication
# destination region differs. Validates the replication_destination_region
# override path without relaxing any security controls.
enable_versioning  = true
enable_lifecycle   = true
enable_logging     = true
enable_replication = true

tags = {
  Environment = "dev"
  Owner       = "platform"
}
