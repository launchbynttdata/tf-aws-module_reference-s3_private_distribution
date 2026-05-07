# Complete Example — Lambda-Based Validation

This complete example deploys a private validation harness for the private distribution bucket collection module.

It validates end-to-end behavior using a **Lambda function** over private networking only:

- S3 artifact access through an interface VPC endpoint
- Lambda function running in private subnets with network-path-only access (no IAM credentials assumed)
- Positive and negative access checks: **200/403/403** (valid object, invalid object, disallowed bucket)

**Key Design**: The Lambda function uses `urllib.request` without boto3 or AWS credentials. This accurately simulates corporate network clients that only have network-path access to S3 endpoints. Validation is purely transport-layer, not IAM-based.

**Note on 403 for missing objects**: The missing-object probe intentionally expects `403` rather than `404`. Through the S3 interface endpoint path used here, a missing key is surfaced as access denied instead of the public-S3-style not found response. This is expected behavior.

## What This Deploys

- VPC with private app subnets
- S3 interface VPC endpoint consumed by the collection module
- Lambda function (Python 3.12) deployed in private subnets
- Lambda execution role (no S3 IAM permissions; access controlled by bucket policy `aws:SourceVpce` condition)
- Lambda security group (HTTPS egress only to VPC CIDR)
- Artifact bucket and sample test objects
- Disallowed bucket/object used for endpoint-policy negative test

## Prerequisites

1. AWS credentials configured locally (`aws sts get-caller-identity` succeeds)
2. Terraform `>= 1.6.0`

## Usage

The complete example calls the module under test from this repository root. The standalone target identity for this module is:

- `tf-aws-module_collection-private_distribution_bucket`

```hcl
module "s3_privatelink" {
  source = "../.."

  vpc_id                  = aws_vpc.main.id
  vpce_subnet_ids         = [for s in aws_subnet.app_private : s.id]
  vpce_security_group_ids = [aws_security_group.vpce.id]

  aws_region  = var.aws_region
  name_prefix = var.name_prefix

  management_principal_arns           = var.management_principal_arns
  pipeline_role_arns                  = var.pipeline_role_arns
  additional_vpce_allowed_bucket_arns = var.additional_vpce_allowed_bucket_arns

  tags = var.tags
}
```

## Running Tests

**Primary path** (automated end-to-end via Go/Terratest):

```bash
make test
```

This command:
1. Plans the Terraform example
2. Deploys the Lambda function and S3 infrastructure (~2-3 min)
3. Invokes the Lambda function to validate network-path access (~5 seconds)
4. Destroys all infrastructure (~10-15 min; S3 cleanup is the bottleneck)

**Expected duration**: ~15-20 minutes total (most time is infrastructure teardown, not validation)

**Manual validation** (if needed during development):

```bash
cd examples/complete
terraform init -backend=false
terraform apply -var-file=test.tfvars

# Invoke Lambda manually
aws lambda invoke --region $(terraform output -raw aws_region) \
  --function-name $(terraform output -raw lambda_function_name) \
  /tmp/response.json && cat /tmp/response.json | jq .

# Clean up
terraform destroy -var-file=test.tfvars
```

## Test Matrix (Tfvars Profiles)

Profile files for this example and expected validation intent:

| Profile | Purpose | Include in default CI | Expected Lambda checks |
|---|---|---|---|
| `test.tfvars` | Baseline secure, full-feature path | Yes | Lambda validates `200/403/403`; endpoint/bucket checks; versioning/lifecycle/logging/replication present |
| `test.external-logging-target.tfvars` | External logging bucket path | Yes | Logging targets external bucket; secure transport constraints remain intact; Lambda `200/403/403` validation passes |
| `test.replication-alt-region.tfvars` | Replication destination-region override | Yes | Replication resources exist and destination-region behavior honored; Lambda validation passes |
| `test.logging-disabled.tfvars` | Logging disabled behavior | No (exploratory) | Expected degraded security mode; Lambda validation still expects `200/403/403` |
| `test.replication-disabled.tfvars` | Replication disabled behavior | No (exploratory) | Expected degraded durability mode; Lambda validation still expects `200/403/403` |
| `test.lifecycle-disabled.tfvars` / `test.versioning-disabled.tfvars` | Lifecycle/versioning disabled behavior | No (exploratory) | Expected degraded retention/version control; Lambda validation still expects `200/403/403` |

**Security note**: Exploratory profiles intentionally relax controls that map to Regula waiver IDs `FG_R00101`, `FG_R00274`, and `FG_R00275` in this module. All profiles maintain the core S3 endpoint policy validation via Lambda.

## Validation Details

### Expected Test Results

The Lambda function tests three scenarios:

1. **Valid existing object** → HTTP `200` (artifact bucket, valid object key)
2. **Invalid/missing object** → HTTP `403` (artifact bucket, non-existent object key)
3. **Disallowed bucket** → HTTP `403` (disallowed bucket, even if object exists)

Each result is captured and reported in JSON format by the Lambda function:

```json
{
  "statusCode": 200,
  "all_passed": true,
  "results": [
    {
      "name": "valid_existing_object",
      "expected": 200,
      "actual": 200,
      "passed": true
    },
    {
      "name": "invalid_missing_object",
      "expected": 403,
      "actual": 403,
      "passed": true
    },
    {
      "name": "disallowed_bucket_object",
      "expected": 403,
      "actual": 403,
      "passed": true
    }
  ]
}
```

### Lambda Implementation

The Lambda function (`lambda_function/index.py`):
- Uses Python 3.12 with `urllib.request` (no boto3, no IAM credentials)
- Runs in private subnets with network connectivity to S3 interface endpoint only
- Environment variables inject bucket names and endpoint hostname at deploy time
- Returns comprehensive JSON response for test assertion

## Teardown

```bash
terraform destroy -var-file=test.tfvars
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
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
|------|------|
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
| [aws_s3_object.sample_note](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_ssm_association.s3_access_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
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
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for test deployment. | `string` | `"us-west-1"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Base naming prefix for all harness and module resources. | `string` | `"msix-s3-complete"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the test VPC. | `string` | `"10.48.0.0/16"` | no |
| <a name="input_app_private_subnet_cidrs"></a> [app\_private\_subnet\_cidrs](#input\_app\_private\_subnet\_cidrs) | CIDRs for private app subnets (one per AZ; receive S3/SSM endpoint ENIs). | `list(string)` | <pre>[<br/>  "10.48.10.0/24",<br/>  "10.48.11.0/24"<br/>]</pre> | no |
| <a name="input_client_subnet_cidr"></a> [client\_subnet\_cidr](#input\_client\_subnet\_cidr) | CIDR for the single-AZ client emulator subnet. | `string` | `"10.48.20.0/24"` | no |
| <a name="input_windows_instance_type"></a> [windows\_instance\_type](#input\_windows\_instance\_type) | EC2 instance type for the Windows client emulator. | `string` | `"t3.large"` | no |
| <a name="input_windows_key_name"></a> [windows\_key\_name](#input\_windows\_key\_name) | Optional EC2 key pair for the Windows instance. Leave null for SSM-only access. | `string` | `null` | no |
| <a name="input_admin_ingress_cidrs"></a> [admin\_ingress\_cidrs](#input\_admin\_ingress\_cidrs) | Optional CIDR blocks for RDP (3389) ingress to the Windows emulator. Empty list keeps RDP closed. | `list(string)` | `[]` | no |
| <a name="input_run_ssm_validation_on_apply"></a> [run\_ssm\_validation\_on\_apply](#input\_run\_ssm\_validation\_on\_apply) | When true, creates an SSM association that runs the private access validation document automatically during apply. Keep false for deterministic applies and trigger validation manually with send-command. | `bool` | `false` | no |
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
|------|-------------|
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the test harness VPC. |
| <a name="output_aws_region"></a> [aws\_region](#output\_aws\_region) | AWS region used by this deployment. |
| <a name="output_app_private_subnet_ids"></a> [app\_private\_subnet\_ids](#output\_app\_private\_subnet\_ids) | IDs of the private app subnets that host the endpoint ENIs. |
| <a name="output_client_subnet_id"></a> [client\_subnet\_id](#output\_client\_subnet\_id) | ID of the client emulator subnet. |
| <a name="output_windows_instance_id"></a> [windows\_instance\_id](#output\_windows\_instance\_id) | Instance ID of the Windows SSM-managed client emulator. |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 artifact bucket created by the collection module. |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 artifact bucket. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint. |
| <a name="output_ssm_interface_vpce_ids"></a> [ssm\_interface\_vpce\_ids](#output\_ssm\_interface\_vpce\_ids) | Interface endpoint IDs for SSM, SSMMessages, and EC2Messages used by Session Manager without internet egress. |
| <a name="output_s3_vpce_bucket_host"></a> [s3\_vpce\_bucket\_host](#output\_s3\_vpce\_bucket\_host) | Bucket-style hostname for the interface endpoint — use as the base URL for private downloads. |
| <a name="output_appinstaller_url"></a> [appinstaller\_url](#output\_appinstaller\_url) | Direct S3 VPCE URL for the sample .appinstaller file. |
| <a name="output_test_urls"></a> [test\_urls](#output\_test\_urls) | Positive/negative URL set for end-to-end validation from the Windows client. The missing-object probe is expected to return 403 over the S3 interface endpoint path. |
| <a name="output_ssm_validation_document_name"></a> [ssm\_validation\_document\_name](#output\_ssm\_validation\_document\_name) | SSM command document that runs the 200/403/403 private access checks from the Windows instance. The missing-object probe is expected to return 403 over the S3 interface endpoint path. |
| <a name="output_ssm_validation_send_command_example"></a> [ssm\_validation\_send\_command\_example](#output\_ssm\_validation\_send\_command\_example) | Example AWS CLI command to run the validation document on demand. |
| <a name="output_ssm_validation_get_invocation_example"></a> [ssm\_validation\_get\_invocation\_example](#output\_ssm\_validation\_get\_invocation\_example) | Example AWS CLI command to fetch command output. Replace COMMAND\_ID with the value returned by send-command. |
<!-- END_TF_DOCS -->
