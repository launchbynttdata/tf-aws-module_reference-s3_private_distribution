# Private Distribution Bucket Collection Module

This folder contains a production-ready Terraform collection module for private software distribution over S3 interface endpoints.

The intended standalone repository identity is `tf-aws-module_collection-private_distribution_bucket`.

## Current Scope

- Provides a reusable collection module surface for private distribution buckets.
- Includes complete and simple examples for validation and integration testing.
- Includes policy testing and Go-based post-deploy verification paths.

## Structure

- Root package files: main.tf, variables.tf, outputs.tf, versions.tf, provider.tf, locals.tf
- Nested examples:
  - examples/simple
  - examples/complete
- Test suites:
  - tests/terraform (terraform test smoke scaffold)
  - tests/post_deploy_functional (Go/Terratest apply + functional validation)
  - tests/post_deploy_functional_readonly (Go/Terratest non-destructive verification)
  - tests/testimpl (shared provider API validation logic)

## Getting Started

Required files and setup:

- **`.golangci.yaml`** — Go linter configuration. This file is tracked in git and required for `make lint` to work. Do not add it to `.gitignore`.
- Run `make configure` to install dependencies and set up pre-commit hooks.
- Run `make lint` to validate the module before testing.

## Testing

- `make test` executes Terraform example planning (`tfmodule/plan`) and then runs functional Go post-deploy tests via `go/test`.
- `make test` currently runs functional Go tests (readonly tests are available as a separate target).
- `make go/readonly_test` runs readonly/non-destructive Go verification.
- `tests/terraform/scaffold.tftest.hcl` exists as a Terraform test scaffold and is not currently wired into `make test`.

## Test Matrix (Tfvars Profiles)

The profiles below are available for explicit scenario coverage in `examples/complete/`.

### Security-gated profiles (recommended for standard CI)

| Profile | Intent | Security posture | Expected assertions |
|---|---|---|---|
| `test.tfvars` | Baseline secure deployment | Secure defaults or explicit secure values (`enable_versioning=true`, `enable_lifecycle=true`, `enable_logging=true`, `enable_replication=true`) | VPC endpoint exists and is interface type; bucket exists; SSM validation returns `200/403/403`; logging/replication/versioning/lifecycle resources are present |
| `test.external-logging-target.tfvars` | Validate external logging bucket integration | Secure if `enable_logging=true` and target bucket policy permits logging writes | `aws_s3_bucket_logging.artifacts` targets external bucket; no auto-created logging bucket; bucket policy + transport controls still enforced |
| `test.replication-alt-region.tfvars` | Validate replication destination override | Secure when replication remains enabled | Replication bucket/resources exist and use specified destination region; replication configuration remains active |

### Exploratory profiles (not recommended for default policy gate)

These are useful for behavior checks, but they relax controls that map to current Regula waiver IDs and security expectations.

| Profile | Counter-control | Related policy/waiver ID | Recommendation |
|---|---|---|---|
| `test.logging-disabled.tfvars` | `enable_logging=false` | `FG_R00274` | Keep out of default CI; run only in exploratory test lane if needed |
| `test.replication-disabled.tfvars` | `enable_replication=false` | `FG_R00275` | Keep out of default CI; run only in exploratory test lane if needed |
| `test.lifecycle-disabled.tfvars` or `test.versioning-disabled.tfvars` | `enable_lifecycle=false` and/or `enable_versioning=false` | `FG_R00101` | Keep out of default CI; use only when intentionally validating degraded mode |

Policy context: waiver files in `components/policy/waivers/` indicate these controls are implemented but currently waived at plan-time interpretation (`FG_R00101`, `FG_R00274`, `FG_R00275`).

## Compliance and Observability Features

## Regula Waiver Rationale (Known Plan-Time Limitations)

This module keeps a small set of Regula waivers in [components/policy/waivers](components/policy/waivers) for two reasons:

1. Plan-time visibility limits for some S3 checks:
  - `FG_R00100` (HTTPS-only policy)
  - `FG_R00101` (versioning/lifecycle)
  - `FG_R00274` (access logging)
  - `FG_R00275` (replication)

  These controls are implemented in Terraform resources in [main.tf](main.tf), but Regula evaluates Terraform plan JSON. For some resources (notably `aws_s3_bucket_policy`), plan values can be unknown until apply time, so Regula cannot always infer effective bucket behavior from the plan alone.

2. Deferred CloudTrail scope owned outside this module:
  - `FG_R00354`
  - `FG_R00355`

  CloudTrail object-level data events are expected to be managed at the shared/account or organization logging layer, not exclusively inside this module.

Guidance for sync/upstream review:
- Keep waiver rationale comments in each waiver file current.
- Keep inline comments near S3 policy resources in [main.tf](main.tf) and [examples/complete/main.tf](examples/complete/main.tf) aligned with waiver reasoning.
- Re-evaluate waivers whenever Regula policy behavior or module architecture changes.

### Suggested Next Steps (Handoff)

If continuing this work later, prioritize the following in order:

1. Tighten waiver scope where possible:
  - Replace rule-wide waivers with resource-specific waivers if supported by policy tooling.
  - Keep `FG_R00354` and `FG_R00355` deferred unless CloudTrail ownership shifts into this module.

2. Add post-apply verification for waived controls:
  - Validate HTTPS enforcement (`DenyInsecureTransport`) on all managed bucket policies.
  - Validate lifecycle, access logging, and replication state with AWS API checks in tests.
  - Treat this as compensating evidence while plan-time waivers remain.

3. Re-test waiver removability after tooling changes:
  - Re-run `make tfmodule/plan` whenever Terraform/policy tooling is upgraded, and re-run your policy check workflow lane in CI.
  - Attempt removing `FG_R00100`, `FG_R00101`, `FG_R00274`, and `FG_R00275` again after upgrades.

4. Keep docs and code comments synchronized:
  - If waiver intent changes, update [components/policy/waivers](components/policy/waivers), [main.tf](main.tf), [examples/complete/main.tf](examples/complete/main.tf), and this README in the same PR.

### S3 Access Logging

Access logging is **enabled by default** to capture all API calls against the S3 bucket. Logs are written to an auto-created private logging bucket with the `artifact-bucket-logs/` prefix. To use an external logging bucket instead:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-private_distribution_bucket"

  enable_logging        = true
  logging_target_bucket = "my-existing-logging-bucket"
  logging_prefix        = "my-app-logs/"

  # ... other variables
}
```

To disable logging entirely, set `enable_logging = false`.

### Object-Level Replication

Replication to a standby bucket is **enabled by default** and replicates objects and versions to a destination bucket. You can disable it explicitly if not needed:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-private_distribution_bucket"

  enable_replication              = false
  replication_destination_region  = "us-east-1"  # Optional; defaults to primary region

  # ... other variables
}
```

When replication is enabled, it is configured with:
- Real-time replication monitoring (15-minute SLA)
- Versioning automatically enabled on both source and destination
- Full object tagging and metadata replication
- Output variables expose the destination bucket name and ARN

### CloudTrail Object-Level Data Events

For comprehensive audit trails of individual S3 GetObject and PutObject operations, configure **CloudTrail data events** at the organization or management account level:

1. Enable CloudTrail logging for S3 data events:
   - Event source: `s3.amazonaws.com`
   - Data resource type: `AWS::S3::Object`
   - Filter to specific bucket ARNs or use `arn:aws:s3:::*/` for all buckets

2. Store CloudTrail logs in a centralized logging bucket with appropriate retention and access controls.

3. Example CloudTrail Terraform configuration:

```hcl
resource "aws_cloudtrail" "s3_data_events" {
  name           = "s3-object-level-logging"
  s3_bucket_name = "your-cloudtrail-bucket"

  event_selector {
    read_write_type           = "All"
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${module.s3_privatelink.s3_bucket_arn}/*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
```

**Note**: CloudTrail data events carry additional costs and generate high volume logs. Implement filtering and lifecycle rules on the CloudTrail bucket to manage costs and retention.

### Lifecycle Management

Lifecycle rules are **enabled by default** to:
- Expire non-current object versions after 90 days (configurable)
- Abort incomplete multipart uploads after 7 days (configurable)

Override these defaults:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-private_distribution_bucket"

  enable_lifecycle                            = true
  lifecycle_noncurrent_version_expiration_days = 30   # Shorten retention
  lifecycle_incomplete_multipart_upload_days  = 3    # Clean up faster

  # ... other variables
}
```

Set `enable_lifecycle = false` to disable all lifecycle rules.

### Versioning

Versioning is **enabled by default** for data protection. Disable with:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_collection-private_distribution_bucket"

  enable_versioning = false

  # ... other variables
}
```

## Implementation Status

Core private distribution bucket behavior is implemented, examples are executable, and policy/waiver guidance is documented. Remaining follow-up work is focused on incremental hardening and naming finalization when this module is promoted to its standalone repository.

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
| <a name="module_artifacts_bucket"></a> [artifacts\_bucket](#module\_artifacts\_bucket) | git::https://github.com/launchbynttdata/tf-aws-module_collection-s3_bucket | 1.1.0 |
| <a name="module_logging_bucket"></a> [logging\_bucket](#module\_logging\_bucket) | git::https://github.com/launchbynttdata/tf-aws-module_collection-s3_bucket | 1.1.0 |
| <a name="module_s3_interface_vpce"></a> [s3\_interface\_vpce](#module\_s3\_interface\_vpce) | ../tf-aws-module_primitive-vpc_endpoint | n/a |
| <a name="module_replication_bucket"></a> [replication\_bucket](#module\_replication\_bucket) | git::https://github.com/launchbynttdata/tf-aws-module_collection-s3_bucket | 1.1.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_s3_bucket_logging.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_policy.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_replication_configuration.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_replication_configuration) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC in which to create the S3 interface endpoint. | `string` | n/a | yes |
| <a name="input_vpce_subnet_ids"></a> [vpce\_subnet\_ids](#input\_vpce\_subnet\_ids) | List of subnet IDs in which to place the endpoint network interfaces. Must be private subnets reachable by artifact consumers. | `list(string)` | n/a | yes |
| <a name="input_vpce_security_group_ids"></a> [vpce\_security\_group\_ids](#input\_vpce\_security\_group\_ids) | Security group IDs to associate with the endpoint ENIs. Must permit inbound HTTPS (443) from consumer CIDRs. | `list(string)` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region where resources are deployed (e.g. us-west-1). Used to construct the S3 endpoint service name. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Base naming prefix applied to all resources created by this module. | `string` | `"msix-s3"` | no |
| <a name="input_additional_vpce_allowed_bucket_arns"></a> [additional\_vpce\_allowed\_bucket\_arns](#input\_additional\_vpce\_allowed\_bucket\_arns) | Optional additional S3 bucket ARNs allowed through the interface endpoint policy. The artifact bucket is always included. | `list(string)` | `[]` | no |
| <a name="input_management_principal_arns"></a> [management\_principal\_arns](#input\_management\_principal\_arns) | Additional principal ARNs (IAM roles, users) to exempt from the VPCE-only read restriction. The caller identity is always included. Accepts both arn:aws:iam:: and arn:aws:sts:: formats; STS assumed-role wildcard patterns are generated automatically. | `list(string)` | `[]` | no |
| <a name="input_pipeline_role_arns"></a> [pipeline\_role\_arns](#input\_pipeline\_role\_arns) | IAM role ARNs granted write access (PutObject, DeleteObject, ListBucket) to the artifact bucket. Each generates a distinct Allow statement so the access is visible in CloudTrail. | `list(string)` | `[]` | no |
| <a name="input_enable_versioning"></a> [enable\_versioning](#input\_enable\_versioning) | Enable versioning on the S3 artifact bucket. Defaults to true for data protection. | `bool` | `true` | no |
| <a name="input_enable_lifecycle"></a> [enable\_lifecycle](#input\_enable\_lifecycle) | Enable lifecycle rules on the S3 artifact bucket to expire old versions and clean up incomplete multipart uploads. | `bool` | `true` | no |
| <a name="input_lifecycle_noncurrent_version_expiration_days"></a> [lifecycle\_noncurrent\_version\_expiration\_days](#input\_lifecycle\_noncurrent\_version\_expiration\_days) | Number of days after which to expire non-current object versions. Only applies if enable\_lifecycle is true. Set to 0 to disable. | `number` | `90` | no |
| <a name="input_lifecycle_incomplete_multipart_upload_days"></a> [lifecycle\_incomplete\_multipart\_upload\_days](#input\_lifecycle\_incomplete\_multipart\_upload\_days) | Number of days after which to abort incomplete multipart uploads. Only applies if enable\_lifecycle is true. Set to 0 to disable. | `number` | `7` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable S3 access logging for the artifact bucket. If enabled, logs can be sent to an auto-created logging bucket or to an externally-provided bucket. | `bool` | `true` | no |
| <a name="input_logging_target_bucket"></a> [logging\_target\_bucket](#input\_logging\_target\_bucket) | Optional S3 bucket to which access logs should be written. If not provided and enable\_logging is true, a logging bucket will be created automatically. Must already exist and allow the artifact bucket to write logs. | `string` | `null` | no |
| <a name="input_logging_prefix"></a> [logging\_prefix](#input\_logging\_prefix) | Path prefix for access logs written to the logging bucket. Only used if enable\_logging is true. | `string` | `"artifact-bucket-logs/"` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Enable S3 replication to a destination bucket in the same or different region. If enabled, a replication destination bucket will be created. | `bool` | `true` | no |
| <a name="input_replication_destination_region"></a> [replication\_destination\_region](#input\_replication\_destination\_region) | AWS region in which to create the replication destination bucket. Only used if enable\_replication is true. If not provided, defaults to the primary region (var.aws\_region). | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto all taggable resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name (ID) of the S3 artifact bucket. |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 artifact bucket. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint (e.g. vpce-0abc123). |
| <a name="output_s3_vpce_dns_entries"></a> [s3\_vpce\_dns\_entries](#output\_s3\_vpce\_dns\_entries) | DNS entries for the S3 interface endpoint. Each entry contains dns\_name and hosted\_zone\_id. |
| <a name="output_s3_vpce_bucket_host"></a> [s3\_vpce\_bucket\_host](#output\_s3\_vpce\_bucket\_host) | Resolved bucket-style hostname for the S3 interface endpoint (e.g. bucket.vpce-xxx.s3.us-west-1.vpce.amazonaws.com). Use as the base URL for private artifact downloads. |
| <a name="output_logging_bucket_name"></a> [logging\_bucket\_name](#output\_logging\_bucket\_name) | Name of the S3 logging bucket (if created). Receives access logs from the artifact bucket. |
| <a name="output_logging_bucket_arn"></a> [logging\_bucket\_arn](#output\_logging\_bucket\_arn) | ARN of the S3 logging bucket (if created). |
| <a name="output_replication_bucket_name"></a> [replication\_bucket\_name](#output\_replication\_bucket\_name) | Name of the S3 replication destination bucket (if created). Receives replicated objects from the artifact bucket. |
| <a name="output_replication_bucket_arn"></a> [replication\_bucket\_arn](#output\_replication\_bucket\_arn) | ARN of the S3 replication destination bucket (if created). |
| <a name="output_replication_bucket_private_base_url"></a> [replication\_bucket\_private\_base\_url](#output\_replication\_bucket\_private\_base\_url) | Bucket base URL for private access to the replication bucket over the S3 interface endpoint hostname. |
<!-- END_TF_DOCS -->
