output "lambda_function_name" {
  description = "Name of the validation Lambda function"
  value       = aws_lambda_function.validation.function_name
}

output "s3_bucket_name" {
  description = "Name of the S3 artifact bucket"
  value       = module.s3_privatelink.s3_bucket_name
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
