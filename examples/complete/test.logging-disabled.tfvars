aws_region                     = "us-east-2"
replication_destination_region = "us-west-1"
name_prefix                    = "msix-s3-no-log"

# Exploratory profile - logging intentionally disabled.
# Related policy waiver: FG_R00274.
# Run only in the exploratory test lane (RUN_EXPLORATORY_COMPLETE_SCENARIOS=true).
enable_versioning  = true
enable_lifecycle   = true
enable_logging     = false
enable_replication = true

tags = {
  Environment = "dev"
  Owner       = "platform"
}
