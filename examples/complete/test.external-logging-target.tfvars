aws_region                     = "us-east-2"
replication_destination_region = "us-west-1"
name_prefix                    = "msix-s3-ext-log"

# External logging profile - routes access logs to the self-managed
# external_logging_target bucket that is created by this example harness
# (named <name_prefix>-ext-log, i.e. msix-s3-ext-log-ext-log).
# No pre-existing bucket is required; the example creates and manages it.
#
# To run this profile:
#   RUN_EXTERNAL_LOGGING_SCENARIO=true make test VAR_FILE=test.external-logging-target.tfvars
use_external_logging_target = true
logging_prefix              = "external-target-logs/"

enable_versioning  = true
enable_lifecycle   = true
enable_logging     = true
enable_replication = true

tags = {
  Environment = "dev"
  Owner       = "platform"
}
