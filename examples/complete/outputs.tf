output "vpc_id" {
  description = "ID of the test harness VPC."
  value       = aws_vpc.main.id
}

output "aws_region" {
  description = "AWS region used by this deployment."
  value       = var.aws_region
}

output "app_private_subnet_ids" {
  description = "IDs of the private app subnets that host the endpoint ENIs."
  value       = [for s in aws_subnet.app_private : s.id]
}

output "client_subnet_id" {
  description = "ID of the client emulator subnet."
  value       = aws_subnet.client.id
}

output "windows_instance_id" {
  description = "Instance ID of the Windows SSM-managed client emulator."
  value       = aws_instance.windows_client.id
}

output "s3_bucket_name" {
  description = "Name of the S3 artifact bucket created by the collection module."
  value       = module.s3_privatelink.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 artifact bucket."
  value       = module.s3_privatelink.s3_bucket_arn
}

output "s3_interface_vpce_id" {
  description = "ID of the S3 interface VPC endpoint."
  value       = module.s3_privatelink.s3_interface_vpce_id
}

output "ssm_interface_vpce_ids" {
  description = "Interface endpoint IDs for SSM, SSMMessages, and EC2Messages used by Session Manager without internet egress."
  value = {
    ssm         = aws_vpc_endpoint.ssm.id
    ssmmessages = aws_vpc_endpoint.ssmmessages.id
    ec2messages = aws_vpc_endpoint.ec2messages.id
  }
}

output "s3_vpce_bucket_host" {
  description = "Bucket-style hostname for the interface endpoint — use as the base URL for private downloads."
  value       = module.s3_privatelink.s3_vpce_bucket_host
}

output "appinstaller_url" {
  description = "Direct S3 VPCE URL for the sample .appinstaller file."
  value       = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/agent-fast.appinstaller"
}

output "test_urls" {
  description = "Positive/negative URL set for end-to-end validation from the Windows client. The missing-object probe is expected to return 403 over the S3 interface endpoint path."
  value = {
    valid_existing_object    = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/agent-fast.appinstaller"
    invalid_missing_object   = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${module.s3_privatelink.s3_bucket_name}/client/latest/does-not-exist.appinstaller"
    disallowed_bucket_object = "https://${module.s3_privatelink.s3_vpce_bucket_host}/${aws_s3_bucket.disallowed_target.id}/client/latest/disallowed.txt"
  }
}

output "ssm_validation_document_name" {
  description = "SSM command document that runs the 200/403/403 private access checks from the Windows instance. The missing-object probe is expected to return 403 over the S3 interface endpoint path."
  value       = aws_ssm_document.s3_access_validation.name
}

output "ssm_validation_send_command_example" {
  description = "Example AWS CLI command to run the validation document on demand."
  value       = "aws ssm send-command --region ${var.aws_region} --document-name ${aws_ssm_document.s3_access_validation.name} --instance-ids ${aws_instance.windows_client.id}"
}

output "ssm_validation_get_invocation_example" {
  description = "Example AWS CLI command to fetch command output. Replace COMMAND_ID with the value returned by send-command."
  value       = "aws ssm get-command-invocation --region ${var.aws_region} --command-id COMMAND_ID --instance-id ${aws_instance.windows_client.id}"
}
