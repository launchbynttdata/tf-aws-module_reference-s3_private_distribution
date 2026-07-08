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

output "artifact_bucket_sse_algorithm" {
  description = "Effective default server-side encryption algorithm for the artifact bucket."
  value       = module.s3_privatelink.artifact_bucket_sse_algorithm
}

output "artifact_bucket_kms_key_arn" {
  description = "Configured customer-managed KMS key ARN for the artifact bucket. Empty string means the module is using its AES256 default path."
  value       = module.s3_privatelink.artifact_bucket_kms_key_arn != null ? module.s3_privatelink.artifact_bucket_kms_key_arn : ""
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

output "logging_bucket_sse_algorithm" {
  description = "Effective default server-side encryption algorithm for the module-managed logging bucket. Empty string means logging is disabled or the target bucket is external to the module."
  value       = module.s3_privatelink.logging_bucket_sse_algorithm != null ? module.s3_privatelink.logging_bucket_sse_algorithm : ""
}

output "logging_bucket_kms_key_arn" {
  description = "Configured customer-managed KMS key ARN for the module-managed logging bucket. Empty string means the module is using its AES256 default or the logging target is external."
  value       = module.s3_privatelink.logging_bucket_kms_key_arn != null ? module.s3_privatelink.logging_bucket_kms_key_arn : ""
}

output "replication_bucket_name" {
  description = "Name of the replication destination bucket. Empty string when replication is disabled."
  value       = module.s3_privatelink.replication_bucket_name != null ? module.s3_privatelink.replication_bucket_name : ""
}

output "replication_bucket_arn" {
  description = "ARN of the replication destination bucket. Empty string when replication is disabled."
  value       = module.s3_privatelink.replication_bucket_arn != null ? module.s3_privatelink.replication_bucket_arn : ""
}

output "replication_bucket_sse_algorithm" {
  description = "Effective default server-side encryption algorithm for the replication destination bucket. Empty string when replication is disabled."
  value       = module.s3_privatelink.replication_bucket_sse_algorithm != null ? module.s3_privatelink.replication_bucket_sse_algorithm : ""
}

output "replication_bucket_kms_key_arn" {
  description = "Configured customer-managed KMS key ARN for the replication destination bucket. Empty string means the module is using its AES256 default or replication is disabled."
  value       = module.s3_privatelink.replication_bucket_kms_key_arn != null ? module.s3_privatelink.replication_bucket_kms_key_arn : ""
}

output "external_logging_target_bucket_name" {
  description = "Name of the self-managed external logging target bucket created by this example. Referenced when use_external_logging_target = true."
  value       = var.use_external_logging_target ? aws_s3_bucket.external_logging_target[0].id : null
}
