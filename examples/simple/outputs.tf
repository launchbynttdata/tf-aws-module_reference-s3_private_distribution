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
