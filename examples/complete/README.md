# Complete Example - Lambda-Based Validation

This complete example deploys a private validation harness for the private S3 distribution reference module.

It validates end-to-end behavior using a **Lambda function** over private networking only:

- S3 artifact access through an interface VPC endpoint
- Lambda function running in private subnets with network-path-only access (no IAM credentials assumed)
- Positive and negative access checks: **200/403/403** (valid object, invalid object, disallowed bucket)

**Key Design**: The Lambda function uses `urllib.request` without boto3 or AWS credentials. This accurately simulates corporate network clients that only have network-path access to S3 endpoints. Validation is purely transport-layer, not IAM-based.

**KMS note**: The module now supports opt-in customer-managed KMS keys for the artifact, logging, and replication buckets. This baseline example keeps the artifact bucket on the default AES256 path because the Lambda harness intentionally uses unsigned, network-path-only reads. If you enable `artifact_bucket_kms_key_arn`, consumer requests must be signed and authorized for KMS decrypt.

**Note on 403 for missing objects**: The missing-object probe intentionally expects `403` rather than `404`. Through the S3 interface endpoint path used here, a missing key is surfaced as access denied instead of the public-S3-style not found response. This is expected behavior.

## What This Deploys

- VPC with private app subnets
- S3 interface VPC endpoint consumed by the reference module
- Lambda function (Python 3.12) deployed in private subnets
- Lambda execution role (no S3 IAM permissions; access controlled by bucket policy `aws:SourceVpce` condition)
- Lambda security group (HTTPS egress only to VPC CIDR)
- Artifact bucket and sample test objects
- Disallowed bucket/object used for endpoint-policy negative test

## Prerequisites

1. AWS credentials configured locally (`aws sts get-caller-identity` succeeds)
2. Terraform `~> 1.10`

## Usage

The complete example calls the module under test from this repository root. The standalone target identity for this module is:

- `tf-aws-module_reference-s3_private_distribution`

```hcl
module "s3_privatelink" {
  source = "../.."

  vpc_id                  = module.vpc.vpc_id
  vpce_subnet_ids         = [for s in module.private_subnets : s.subnet_id]
  vpce_security_group_ids = [module.s3_vpce_sg.id]

  aws_region           = var.aws_region
  name_prefix          = var.name_prefix
  vpce_auto_accept     = var.vpce_auto_accept
  vpce_private_dns_enabled = var.vpce_private_dns_enabled
  vpce_ip_address_type = var.vpce_ip_address_type
  vpce_dns_options     = var.vpce_dns_options

  management_principal_arns           = local.effective_management_principal_arns
  pipeline_role_arns                  = var.pipeline_role_arns
  additional_vpce_allowed_bucket_arns = []

  enable_versioning                            = var.enable_versioning
  enable_lifecycle                             = var.enable_lifecycle
  lifecycle_noncurrent_version_expiration_days = var.lifecycle_noncurrent_version_expiration_days
  lifecycle_incomplete_multipart_upload_days   = var.lifecycle_incomplete_multipart_upload_days
  enable_logging                               = var.enable_logging
  logging_target_bucket                        = local.effective_logging_target_bucket
  logging_prefix                               = var.logging_prefix
  artifact_bucket_kms_key_arn                  = var.artifact_bucket_kms_key_arn
  logging_bucket_kms_key_arn                   = var.logging_bucket_kms_key_arn
  enable_replication                           = var.enable_replication
  replication_destination_region               = var.replication_destination_region
  replication_bucket_kms_key_arn               = var.replication_bucket_kms_key_arn

  tags = var.tags
}
```

The example computes `local.effective_management_principal_arns` so that when
`management_principal_arns` is not explicitly set, local/CI runs can still
proceed by trusting the current execution principal (including assumed-role
caller normalization).

## Running Tests

**Primary path** (automated end-to-end via Go/Terratest):

```bash
# Always pass AWS_REGION explicitly.
# The dev container default (us-west-2) overrides the Makefile's built-in
# default (us-east-2), and a wrong region deploys infrastructure out of
# the expected account quota and test setup.
make test AWS_REGION=us-east-2
```

> **Common first failure**: If `vpce_dns_options.private_dns_only_for_inbound_resolver_endpoint = true`, AWS requires an S3 Gateway endpoint in the same VPC.
> This complete example uses an interface endpoint-only topology, so baseline `test.tfvars` pins `private_dns_only_for_inbound_resolver_endpoint = false`.
> If you change it to `true`, also add an S3 Gateway endpoint to the harness before running `make test`.

> **Region precondition**: the example's `data.aws_availability_zones.available` block
> includes a `lifecycle { precondition }` that aborts `terraform plan` if the active AWS
> provider region does not match `var.aws_region` from the tfvars file. This guard
> catches accidental region drift early rather than mid-apply.

This command:
1. Plans the Terraform example (the precondition verifies provider region == var.aws_region)
2. Deploys the Lambda function and S3 infrastructure (~10-15 min; VPC endpoint ENI provisioning is the main driver)
3. Invokes the Lambda function to validate network-path access (~5 seconds)
4. Destroys all infrastructure (~10-15 min; S3 cleanup is the bottleneck)
5. After destroy, automatically verifies the artifacts bucket, disallowed bucket, and Lambda function are absent in AWS (`verifyResourcesDestroyed` via `t.Cleanup` in `tests/testimpl/test_impl.go`)

Region defaults used by the test profile are `aws_region = us-east-2` and `replication_destination_region = us-west-1`.

**Expected duration**: ~35-45 minutes total. The test harness runs two full `terraform apply` cycles to verify idempotency (`IS_TERRAFORM_IDEMPOTENT_APPLY = true`). VPC interface endpoint ENI provisioning is the largest single contributor (~5-8 min); versioned S3 bucket destruction accounts for most of teardown time.

**Current validation status (2026-07-09)**: baseline `terraform apply`/`destroy`, `make test`, `make lint`, focused functional rerun (`go test ./tests/post_deploy_functional -run TestS3BucketCollectionFunctional`), and readonly verification (`go test ./tests/post_deploy_functional_readonly -run TestS3BucketCollectionReadonly`) were run successfully in this PR workflow.

### Deploy-Then-Readonly Workflow

Use this when you want to validate readonly behavior against live infrastructure without automatic teardown.

1. From repository root, generate example provider files:

```bash
make tfmodule/create_example_providers AWS_REGION=us-east-2 AWS_PROFILE=default
```

2. Deploy this example:

```bash
terraform -chdir=examples/complete init -backend=false
terraform -chdir=examples/complete apply -var-file=test.tfvars
```

3. Run readonly test entrypoint:

```bash
go test -v -count=1 -timeout=2h ./tests/post_deploy_functional_readonly -run TestS3BucketCollectionReadonly
```

Optional Make target:

```bash
make go/readonly_test
```

4. Tear down after readonly verification:

```bash
terraform -chdir=examples/complete destroy -var-file=test.tfvars
```

Notes:

- Keep `AWS_REGION` aligned with `test.tfvars` (`us-east-2`) to avoid precondition failures.
- Readonly tests use `RunNonDestructiveTest` and do not create or destroy infrastructure.

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

## Baseline Profile

Default PR validation for this example is centered on `test.tfvars`.

Active profile set in this folder is intentionally baseline-only (`test.tfvars`).

Expected checks:

- Lambda returns `200/403/403` for valid object, missing object, and disallowed bucket probes.
- Endpoint and bucket policy controls remain enforced through the private network path.
- Bucket encryption state is verified through the S3 API for the artifact bucket and, when present, the module-managed logging and replication buckets.
- Baseline security controls (versioning, lifecycle, logging, replication) are configured from the secure profile inputs.

Additional scenario permutations are treated as follow-up work outside this baseline acceptance path.

## Validation Details

### Expected Test Results

The Lambda function tests three scenarios:

1. **Valid existing object** -> HTTP `200` (artifact bucket, valid object key)
2. **Invalid/missing object** -> HTTP `403` (artifact bucket, non-existent object key)
3. **Disallowed bucket** -> HTTP `403` (disallowed bucket, even if object exists)

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
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.4 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.100, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform.registry.launch.nttdata.com/module_primitive/vpc/aws | ~> 1.0 |
| <a name="module_private_subnets"></a> [private\_subnets](#module\_private\_subnets) | terraform.registry.launch.nttdata.com/module_primitive/subnet/aws | ~> 1.0 |
| <a name="module_s3_vpce_sg"></a> [s3\_vpce\_sg](#module\_s3\_vpce\_sg) | terraform.registry.launch.nttdata.com/module_primitive/security_group/aws | ~> 0.7 |
| <a name="module_s3_vpce_sg_ingress"></a> [s3\_vpce\_sg\_ingress](#module\_s3\_vpce\_sg\_ingress) | terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws | ~> 0.1.4 |
| <a name="module_lambda_sg"></a> [lambda\_sg](#module\_lambda\_sg) | terraform.registry.launch.nttdata.com/module_primitive/security_group/aws | ~> 0.7 |
| <a name="module_s3_privatelink"></a> [s3\_privatelink](#module\_s3\_privatelink) | ../.. | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_default_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_iam_role.lambda_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.lambda_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_s3_bucket.disallowed_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.external_logging_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.external_logging_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.disallowed_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.external_logging_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.disallowed_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.external_logging_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_object.disallowed_probe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.sample_appinstaller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_vpc_security_group_egress_rule.lambda_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [random_id.lambda_resources_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_string.disallowed_bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [archive_file.lambda_package](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.lambda_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_role.current_assumed_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for resource deployment. | `string` | `"us-east-2"` | no |
| <a name="input_vpce_auto_accept"></a> [vpce\_auto\_accept](#input\_vpce\_auto\_accept) | Whether to auto-accept the interface endpoint request. | `bool` | `false` | no |
| <a name="input_vpce_private_dns_enabled"></a> [vpce\_private\_dns\_enabled](#input\_vpce\_private\_dns\_enabled) | Whether to enable private DNS for the S3 interface endpoint. | `bool` | `true` | no |
| <a name="input_vpce_ip_address_type"></a> [vpce\_ip\_address\_type](#input\_vpce\_ip\_address\_type) | IP address type for the interface endpoint (ipv4, dualstack, ipv6). Null uses service default. | `string` | `null` | no |
| <a name="input_vpce_dns_options"></a> [vpce\_dns\_options](#input\_vpce\_dns\_options) | Optional DNS behavior for the interface endpoint. | <pre>object({<br/>    dns_record_ip_type                             = optional(string)<br/>    private_dns_only_for_inbound_resolver_endpoint = optional(bool)<br/>  })</pre> | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names. | `string` | `"launch-s3probe"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDR blocks for private subnets (one per AZ). | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_lambda_runtime"></a> [lambda\_runtime](#input\_lambda\_runtime) | Lambda runtime for the validation function. | `string` | `"python3.12"` | no |
| <a name="input_management_principal_arns"></a> [management\_principal\_arns](#input\_management\_principal\_arns) | Explicit Terraform/CI principal ARNs allowed to bypass VPCE-only restrictions. | `list(string)` | `[]` | no |
| <a name="input_pipeline_role_arns"></a> [pipeline\_role\_arns](#input\_pipeline\_role\_arns) | ARNs of pipeline roles allowed to access the bucket. | `list(string)` | `[]` | no |
| <a name="input_enable_versioning"></a> [enable\_versioning](#input\_enable\_versioning) | Enable versioning on the S3 bucket. | `bool` | `false` | no |
| <a name="input_enable_lifecycle"></a> [enable\_lifecycle](#input\_enable\_lifecycle) | Enable lifecycle rules on the bucket. | `bool` | `true` | no |
| <a name="input_lifecycle_noncurrent_version_expiration_days"></a> [lifecycle\_noncurrent\_version\_expiration\_days](#input\_lifecycle\_noncurrent\_version\_expiration\_days) | Days to retain noncurrent versions before expiration. | `number` | `30` | no |
| <a name="input_lifecycle_incomplete_multipart_upload_days"></a> [lifecycle\_incomplete\_multipart\_upload\_days](#input\_lifecycle\_incomplete\_multipart\_upload\_days) | Days to retain incomplete multipart uploads. | `number` | `7` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable S3 access logging. | `bool` | `false` | no |
| <a name="input_logging_target_bucket"></a> [logging\_target\_bucket](#input\_logging\_target\_bucket) | Target bucket for access logs. Mutually exclusive with use\_external\_logging\_target. | `string` | `null` | no |
| <a name="input_use_external_logging_target"></a> [use\_external\_logging\_target](#input\_use\_external\_logging\_target) | When true, routes S3 access logs to the self-managed external logging target bucket created by this example (named <name\_prefix>-ext-log) instead of the auto-created logging bucket inside the root module. | `bool` | `false` | no |
| <a name="input_logging_prefix"></a> [logging\_prefix](#input\_logging\_prefix) | Prefix for access logs. | `string` | `"logs/"` | no |
| <a name="input_artifact_bucket_kms_key_arn"></a> [artifact\_bucket\_kms\_key\_arn](#input\_artifact\_bucket\_kms\_key\_arn) | Optional customer-managed KMS key ARN for the artifact bucket. Null preserves the baseline AES256 path used by the network-only validation harness. | `string` | `null` | no |
| <a name="input_logging_bucket_kms_key_arn"></a> [logging\_bucket\_kms\_key\_arn](#input\_logging\_bucket\_kms\_key\_arn) | Optional customer-managed KMS key ARN for the module-managed logging bucket. Null preserves the module default AES256 path. | `string` | `null` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Enable cross-region replication. | `bool` | `false` | no |
| <a name="input_replication_destination_region"></a> [replication\_destination\_region](#input\_replication\_destination\_region) | Destination region for replication. | `string` | `null` | no |
| <a name="input_replication_bucket_kms_key_arn"></a> [replication\_bucket\_kms\_key\_arn](#input\_replication\_bucket\_kms\_key\_arn) | Optional customer-managed KMS key ARN for the replication destination bucket. Null preserves the module default AES256 path. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. | `map(string)` | <pre>{<br/>  "Purpose": "S3-PrivateLink-Validation",<br/>  "Terraform": "true"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_lambda_function_name"></a> [lambda\_function\_name](#output\_lambda\_function\_name) | Name of the validation Lambda function |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 artifact bucket |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 artifact bucket |
| <a name="output_artifact_bucket_sse_algorithm"></a> [artifact\_bucket\_sse\_algorithm](#output\_artifact\_bucket\_sse\_algorithm) | Effective default server-side encryption algorithm for the artifact bucket. |
| <a name="output_artifact_bucket_kms_key_arn"></a> [artifact\_bucket\_kms\_key\_arn](#output\_artifact\_bucket\_kms\_key\_arn) | Configured customer-managed KMS key ARN for the artifact bucket. Empty string means the module is using its AES256 default path. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint |
| <a name="output_s3_vpce_bucket_host"></a> [s3\_vpce\_bucket\_host](#output\_s3\_vpce\_bucket\_host) | Bucket-style hostname for the S3 interface endpoint |
| <a name="output_disallowed_bucket_name"></a> [disallowed\_bucket\_name](#output\_disallowed\_bucket\_name) | Name of the disallowed bucket (used for negative validation) |
| <a name="output_aws_region"></a> [aws\_region](#output\_aws\_region) | AWS region |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID |
| <a name="output_logging_bucket_name"></a> [logging\_bucket\_name](#output\_logging\_bucket\_name) | Name of the S3 logging target bucket (auto-created or externally supplied). Empty string when logging is disabled. |
| <a name="output_logging_bucket_sse_algorithm"></a> [logging\_bucket\_sse\_algorithm](#output\_logging\_bucket\_sse\_algorithm) | Effective default server-side encryption algorithm for the module-managed logging bucket. Empty string means logging is disabled or the target bucket is external to the module. |
| <a name="output_logging_bucket_kms_key_arn"></a> [logging\_bucket\_kms\_key\_arn](#output\_logging\_bucket\_kms\_key\_arn) | Configured customer-managed KMS key ARN for the module-managed logging bucket. Empty string means the module is using its AES256 default or the logging target is external. |
| <a name="output_replication_bucket_name"></a> [replication\_bucket\_name](#output\_replication\_bucket\_name) | Name of the replication destination bucket. Empty string when replication is disabled. |
| <a name="output_replication_bucket_arn"></a> [replication\_bucket\_arn](#output\_replication\_bucket\_arn) | ARN of the replication destination bucket. Empty string when replication is disabled. |
| <a name="output_replication_bucket_sse_algorithm"></a> [replication\_bucket\_sse\_algorithm](#output\_replication\_bucket\_sse\_algorithm) | Effective default server-side encryption algorithm for the replication destination bucket. Empty string when replication is disabled. |
| <a name="output_replication_bucket_kms_key_arn"></a> [replication\_bucket\_kms\_key\_arn](#output\_replication\_bucket\_kms\_key\_arn) | Configured customer-managed KMS key ARN for the replication destination bucket. Empty string means the module is using its AES256 default or replication is disabled. |
| <a name="output_external_logging_target_bucket_name"></a> [external\_logging\_target\_bucket\_name](#output\_external\_logging\_target\_bucket\_name) | Name of the self-managed external logging target bucket created by this example. Referenced when use\_external\_logging\_target = true. |
<!-- END_TF_DOCS -->
