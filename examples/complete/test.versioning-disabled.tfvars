aws_region  = "us-east-2"
name_prefix = "msix-s3-no-ver"

# Exploratory profile - versioning intentionally disabled.
# Replication is co-disabled because S3 replication requires versioning on
# the source bucket. Enabling replication with versioning off would be
# rejected by AWS and is now caught at plan time by a lifecycle precondition
# on aws_s3_bucket_replication_configuration.artifacts.
# Related policy waiver: FG_R00101.
# Run only in the exploratory test lane (RUN_EXPLORATORY_COMPLETE_SCENARIOS=true).
enable_versioning  = false
enable_lifecycle   = true
enable_logging     = true
enable_replication = false

tags = {
  Environment = "dev"
  Owner       = "platform"
}
