# ---------------------------------------------------------------------------
# Provider aliases
#
# aws.replication is passed to the root module's replication_bucket child
# module so the destination bucket is always created in the correct region.
# The simple example does not enable cross-region replication (the provider
# alias is still required because the root module declares it), so it is
# configured for the same region as the primary provider.
# ---------------------------------------------------------------------------

provider "aws" {
  alias  = "replication"
  region = var.aws_region
}
