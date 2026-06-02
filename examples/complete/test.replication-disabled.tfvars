aws_region  = "us-east-2"
name_prefix = "msix-s3-no-repl"

# Exploratory profile - replication intentionally disabled.
# Related policy waiver: FG_R00275.
# Run only in the exploratory test lane (RUN_EXPLORATORY_COMPLETE_SCENARIOS=true).
enable_versioning  = true
enable_lifecycle   = true
enable_logging     = true
enable_replication = false

tags = {
  Environment = "dev"
  Owner       = "platform"
}
