# ---------------------------------------------------------------------------
# Provider aliases
#
# aws.replication is passed to the root module's replication_bucket child
# module so the destination bucket is always created in the correct region,
# even when replication_destination_region differs from the primary region.
# ---------------------------------------------------------------------------

provider "aws" {
  alias  = "replication"
  region = var.replication_destination_region != null ? var.replication_destination_region : var.aws_region
}
