output "windows_instance_id" {
  description = "Instance ID of the Windows SSM-managed client."
  value       = aws_instance.windows_client.id
}

output "ssm_validation_document_name" {
  description = "Name of the SSM document to run the 200/403/403 validation."
  value       = aws_ssm_document.s3_access_validation.name
}

output "ssm_send_command_example" {
  description = "AWS CLI command to trigger the validation document."
  value       = "aws ssm send-command --region ${var.aws_region} --document-name ${aws_ssm_document.s3_access_validation.name} --instance-ids ${aws_instance.windows_client.id}"
}

output "ssm_get_invocation_example" {
  description = "AWS CLI command to retrieve output. Replace COMMAND_ID with the value returned by send-command."
  value       = "aws ssm get-command-invocation --region ${var.aws_region} --command-id COMMAND_ID --instance-id ${aws_instance.windows_client.id}"
}

output "s3_bucket_name" {
  description = "Name of the S3 artifact bucket."
  value       = module.s3_privatelink.s3_bucket_name
}

output "s3_interface_vpce_id" {
  description = "ID of the S3 interface VPC endpoint."
  value       = module.s3_privatelink.s3_interface_vpce_id
}

output "vpc_id" {
  description = "ID of the test VPC."
  value       = module.vpc.vpc_id
}
