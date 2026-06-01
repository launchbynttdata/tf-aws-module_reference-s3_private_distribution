output "lambda_function_name" {
  description = "Name of the validation Lambda function"
  value       = aws_lambda_function.validation.function_name
}

output "s3_bucket_name" {
  description = "Name of the S3 artifact bucket"
  value       = module.s3_privatelink.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 artifact bucket"
  value       = module.s3_privatelink.s3_bucket_arn
}

output "s3_interface_vpce_id" {
  description = "ID of the S3 interface VPC endpoint"
  value       = module.s3_privatelink.s3_interface_vpce_id
}

output "s3_vpce_bucket_host" {
  description = "Bucket-style hostname for the S3 interface endpoint"
  value       = module.s3_privatelink.s3_vpce_bucket_host
}

output "disallowed_bucket_name" {
  description = "Name of the disallowed bucket (used for negative validation)"
  value       = aws_s3_bucket.disallowed_target.id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "logging_bucket_name" {
  description = "Name of the S3 logging target bucket (auto-created or externally supplied). Empty string when logging is disabled."
  value       = module.s3_privatelink.logging_bucket_name != null ? module.s3_privatelink.logging_bucket_name : ""
}

output "replication_bucket_arn" {
  description = "ARN of the replication destination bucket. Empty string when replication is disabled."
  value       = module.s3_privatelink.replication_bucket_arn != null ? module.s3_privatelink.replication_bucket_arn : ""
}

output "external_logging_target_bucket_name" {
  description = "Name of the self-managed external logging target bucket created by this example. Referenced when use_external_logging_target = true."
  value       = aws_s3_bucket.external_logging_target.id
}
