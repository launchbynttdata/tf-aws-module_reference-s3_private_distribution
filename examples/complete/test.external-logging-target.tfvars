aws_region                     = "us-east-2"
replication_destination_region = "us-west-1"
name_prefix                    = "msix-s3-ext-log"

# External logging profile — routes access logs to a pre-existing target bucket
# instead of the auto-created logging bucket. Replace the placeholder below with
# an actual bucket name before running the RUN_EXTERNAL_LOGGING_SCENARIO test lane.
#
# Pre-requisites:
#   1. The target bucket must exist in the same region as the primary bucket (us-east-2).
#   2. The target bucket must allow s3.amazonaws.com (logging service) to PutObject via
#      its bucket policy (aws:SourceArn and aws:SourceAccount conditions recommended).
#
# To run this profile:
#   RUN_EXTERNAL_LOGGING_SCENARIO=true make test VAR_FILE=test.external-logging-target.tfvars
logging_target_bucket = "REPLACE-WITH-PRE-EXISTING-LOGGING-BUCKET-NAME"
logging_prefix        = "external-target-logs/"

enable_versioning  = true
enable_lifecycle   = true
enable_logging     = true
enable_replication = true

tags = {
  Environment = "dev"
  Owner       = "platform"
}
