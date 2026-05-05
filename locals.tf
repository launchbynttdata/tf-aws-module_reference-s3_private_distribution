locals {
  suffix         = random_string.suffix.result
  base_name      = "${var.name_prefix}-${local.suffix}"
  s3_bucket_name = lower(replace("${local.base_name}-artifacts", "_", "-"))

  tags = merge(
    {
      Name              = local.base_name
      Project           = "msix-s3-vpce"
      LogicalOwner      = var.name_prefix
      DeploymentPattern = "option-b-s3-vpce"
      ManagedBy         = "terraform"
    },
    var.tags
  )
}
