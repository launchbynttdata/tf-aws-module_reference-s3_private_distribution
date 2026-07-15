output "s3_bucket_name" {
  description = "Name of the S3 artifact bucket created by the reference module."
  value       = module.s3_privatelink.s3_bucket_name
}

output "s3_interface_vpce_id" {
  description = "ID of the S3 interface VPC endpoint."
  value       = module.s3_privatelink.s3_interface_vpce_id
}

output "s3_vpce_bucket_host" {
  description = "Bucket-style hostname for the interface endpoint."
  value       = module.s3_privatelink.s3_vpce_bucket_host
}

output "s3_vpce_regional_dns_names" {
  description = "Regional DNS names discovered from the S3 interface endpoint DNS entries."
  value       = module.s3_privatelink.s3_vpce_regional_dns_names
}

output "s3_vpce_zonal_dns_names" {
  description = "Zonal DNS names discovered from the S3 interface endpoint DNS entries."
  value       = module.s3_privatelink.s3_vpce_zonal_dns_names
}

output "s3_vpce_validation_hosts" {
  description = "Ordered DNS host candidates for downstream validation. Starts with the preferred regional bucket-style host, followed by zonal and all other endpoint-derived names."
  value       = module.s3_privatelink.s3_vpce_validation_hosts
}
