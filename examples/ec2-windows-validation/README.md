# EC2 Windows Validation Example (Manual Reference)

Manual-use reference harness that validates end-to-end private S3 access from
a Windows Server 2022 instance via SSM Run Command (no public internet path).

**⚠️ This example is NOT part of the automated test suite.** Automated testing now uses the `examples/complete/` example, which deploys a Lambda function for faster, simpler network-path-only validation.

**Use this example when**: You need to manually verify Windows-to-S3 endpoint connectivity in your own account, or you're debugging SSM/Session Manager behavior.

## Prerequisites

- AWS credentials with EC2, S3, SSM, and IAM permissions
- A `test.tfvars` based on the variable defaults (see `variables.tf`)

## Usage

```bash
terraform init
terraform apply -var-file test.tfvars

# Wait for the Windows instance to appear Online in SSM (typically 5–15 minutes).
# Check status:
aws ssm describe-instance-information \
  --region us-east-2 \
  --filters Key=InstanceIds,Values=$(terraform output -raw windows_instance_id)

# Run the 200/403/403 validation:
aws ssm send-command \
  --region us-east-2 \
  --document-name $(terraform output -raw ssm_validation_document_name) \
  --instance-ids $(terraform output -raw windows_instance_id)

# Retrieve results (replace COMMAND_ID):
aws ssm get-command-invocation \
  --region us-east-2 \
  --command-id COMMAND_ID \
  --instance-id $(terraform output -raw windows_instance_id)
```

## Networking

All SSM endpoints and the Windows instance are placed in `local.primary_az`
(the first available AZ). The S3 interface endpoint spans two AZs via the
`app_private_subnets`. No IGW or NAT — all AWS API traffic flows via VPC
interface endpoints.

## Validation Probes

| Probe | Expected | Meaning |
|---|---|---|
| `valid_existing_object` | 200 | Object reachable via endpoint |
| `invalid_missing_object` | 403 | Missing object returns 403 (not 404) over interface endpoint |
| `disallowed_bucket_object` | 403 | Endpoint policy blocks access to non-allowlisted bucket |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc | 1.0.5 |
| <a name="module_app_private_subnets"></a> [app\_private\_subnets](#module\_app\_private\_subnets) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-subnet | 1.0.5 |
| <a name="module_client_subnet"></a> [client\_subnet](#module\_client\_subnet) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-subnet | 1.0.5 |
| <a name="module_vpce_sg"></a> [vpce\_sg](#module\_vpce\_sg) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-security_group | 0.7.3 |
| <a name="module_vpce_sg_ingress"></a> [vpce\_sg\_ingress](#module\_vpce\_sg\_ingress) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc_security_group_ingress_rule | 0.1.4 |
| <a name="module_windows_client_sg"></a> [windows\_client\_sg](#module\_windows\_client\_sg) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-security_group | 0.7.3 |
| <a name="module_windows_client_sg_rdp_ingress"></a> [windows\_client\_sg\_rdp\_ingress](#module\_windows\_client\_sg\_rdp\_ingress) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc_security_group_ingress_rule | 0.1.4 |
| <a name="module_ssm_endpoints_sg"></a> [ssm\_endpoints\_sg](#module\_ssm\_endpoints\_sg) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-security_group | 0.7.3 |
| <a name="module_ssm_endpoints_sg_ingress"></a> [ssm\_endpoints\_sg\_ingress](#module\_ssm\_endpoints\_sg\_ingress) | git::https://github.com/launchbynttdata/tf-aws-module_primitive-vpc_security_group_ingress_rule | 0.1.4 |
| <a name="module_s3_privatelink"></a> [s3\_privatelink](#module\_s3\_privatelink) | ../.. | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_default_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_iam_instance_profile.windows_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.windows_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.windows_ssm_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.windows_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_s3_bucket.disallowed_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_policy.disallowed_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.disallowed_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_object.disallowed_probe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.sample_appinstaller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_ssm_document.s3_access_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_vpc_endpoint.ec2messages](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ssmmessages](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [random_id.windows_resources_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_string.disallowed_bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_iam_policy_document.ec2_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_ssm_parameter.windows_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for test deployment. | `string` | `"us-west-1"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Base naming prefix for all harness and module resources. | `string` | `"msix-s3-complete"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the test VPC. | `string` | `"10.48.0.0/16"` | no |
| <a name="input_app_private_subnet_cidrs"></a> [app\_private\_subnet\_cidrs](#input\_app\_private\_subnet\_cidrs) | CIDRs for private app subnets (one per AZ; receive S3/SSM endpoint ENIs). | `list(string)` | <pre>[<br/>  "10.48.10.0/24",<br/>  "10.48.11.0/24"<br/>]</pre> | no |
| <a name="input_client_subnet_cidr"></a> [client\_subnet\_cidr](#input\_client\_subnet\_cidr) | CIDR for the single-AZ client emulator subnet. | `string` | `"10.48.20.0/24"` | no |
| <a name="input_windows_instance_type"></a> [windows\_instance\_type](#input\_windows\_instance\_type) | EC2 instance type for the Windows client emulator. | `string` | `"t3.large"` | no |
| <a name="input_windows_key_name"></a> [windows\_key\_name](#input\_windows\_key\_name) | Optional EC2 key pair for the Windows instance. Leave null for SSM-only access. | `string` | `null` | no |
| <a name="input_admin_ingress_cidrs"></a> [admin\_ingress\_cidrs](#input\_admin\_ingress\_cidrs) | Optional CIDR blocks for RDP (3389) ingress to the Windows emulator. Empty list keeps RDP closed. | `list(string)` | `[]` | no |
| <a name="input_management_principal_arns"></a> [management\_principal\_arns](#input\_management\_principal\_arns) | Principal ARNs exempted from the VPCE-only read restriction (passed to collection module). | `list(string)` | `[]` | no |
| <a name="input_pipeline_role_arns"></a> [pipeline\_role\_arns](#input\_pipeline\_role\_arns) | IAM role ARNs granted write access to the artifact bucket (passed to collection module). | `list(string)` | `[]` | no |
| <a name="input_additional_vpce_allowed_bucket_arns"></a> [additional\_vpce\_allowed\_bucket\_arns](#input\_additional\_vpce\_allowed\_bucket\_arns) | Additional S3 bucket ARNs allowed through the endpoint policy (passed to collection module). | `list(string)` | `[]` | no |
| <a name="input_enable_versioning"></a> [enable\_versioning](#input\_enable\_versioning) | Pass-through: enable versioning on the collection module artifact bucket. | `bool` | `true` | no |
| <a name="input_enable_lifecycle"></a> [enable\_lifecycle](#input\_enable\_lifecycle) | Pass-through: enable lifecycle rules on the collection module artifact bucket. | `bool` | `true` | no |
| <a name="input_lifecycle_noncurrent_version_expiration_days"></a> [lifecycle\_noncurrent\_version\_expiration\_days](#input\_lifecycle\_noncurrent\_version\_expiration\_days) | Pass-through: non-current object expiration days for lifecycle rules. | `number` | `90` | no |
| <a name="input_lifecycle_incomplete_multipart_upload_days"></a> [lifecycle\_incomplete\_multipart\_upload\_days](#input\_lifecycle\_incomplete\_multipart\_upload\_days) | Pass-through: days to abort incomplete multipart uploads. | `number` | `7` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Pass-through: enable S3 access logging behavior in the collection module. | `bool` | `true` | no |
| <a name="input_logging_target_bucket"></a> [logging\_target\_bucket](#input\_logging\_target\_bucket) | Pass-through: optional external logging target bucket. If null, module-managed logging bucket is used when logging is enabled. | `string` | `null` | no |
| <a name="input_logging_prefix"></a> [logging\_prefix](#input\_logging\_prefix) | Pass-through: prefix for S3 access logs. | `string` | `"artifact-bucket-logs/"` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Pass-through: enable replication behavior in the collection module. | `bool` | `true` | no |
| <a name="input_replication_destination_region"></a> [replication\_destination\_region](#input\_replication\_destination\_region) | Pass-through: optional destination region for replication bucket creation. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_windows_instance_id"></a> [windows\_instance\_id](#output\_windows\_instance\_id) | Instance ID of the Windows SSM-managed client. |
| <a name="output_ssm_validation_document_name"></a> [ssm\_validation\_document\_name](#output\_ssm\_validation\_document\_name) | Name of the SSM document to run the 200/403/403 validation. |
| <a name="output_ssm_send_command_example"></a> [ssm\_send\_command\_example](#output\_ssm\_send\_command\_example) | AWS CLI command to trigger the validation document. |
| <a name="output_ssm_get_invocation_example"></a> [ssm\_get\_invocation\_example](#output\_ssm\_get\_invocation\_example) | AWS CLI command to retrieve output. Replace COMMAND\_ID with the value returned by send-command. |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 artifact bucket. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the test VPC. |
<!-- END_TF_DOCS -->
