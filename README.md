# Private S3 Distribution Reference Module

This repository provides a purpose-built reference module for private S3-backed internal distribution: an artifacts bucket reachable through an S3 interface endpoint, explicit management and pipeline write principals, secure transport enforcement, and baseline logging/replication controls that produce auditable evidence of access-path behavior.

Repository identity: `tf-aws-module_reference-s3_private_distribution`.

## Current Scope

- Keep `examples/complete` as the single secure baseline for this PR.
- Prove core controls with one apply/destroy path and one readonly evidence path.
- Keep exploratory or degraded profile work out of the baseline review path.

## Structure

- Root package files: main.tf, variables.tf, outputs.tf, versions.tf, locals.tf
  - Note: the replication provider alias is defined directly in `main.tf`; there is no separate `provider.tf` in the root module
- Nested examples:
  - examples/simple
  - examples/complete
- Test suites:
  - tests/terraform (terraform baseline plan scaffold)
  - tests/post_deploy_functional (Go/Terratest apply + functional validation)
  - tests/post_deploy_functional_readonly (Go/Terratest non-destructive verification)
  - tests/testimpl (shared provider API validation logic)

## Artifacts Bucket Policy Design

The artifacts bucket policy enforces private access through a layered model. Three statement groups are applied in order of evaluation:

### Statement 1 - `DenyInsecureTransport`
Denies all S3 actions unconditionally unless `aws:SecureTransport = true`. Applies to every principal and request type with no exceptions.

### Statement 2 - `DenyAccessOutsideVPCEndpoint`
Denies key S3 read/write actions (`GetObject`, `ListBucket`, `PutObject`, `DeleteObject`, etc.) unless the request arrives through the managed S3 interface VPC endpoint (`aws:SourceVpce`).

An explicit bypass can be granted only for configured management principals via `management_principal_arns`. Bypass matching uses wildcard-compatible `aws:PrincipalArn` patterns so IAM Identity Center STS sessions match reliably.

### Statement 3 - `AllowClientReadViaVPCEndpoint`
Explicitly allows `s3:GetObject` when `aws:SourceVpce` matches the managed endpoint and transport is secure. This is the primary distribution read path for artifact consumers inside allowed subnets.

> **Why not `aws:SourceIp` conditions?**
>
> S3 interface endpoints mask the client's true source IP with the endpoint ENI's private IP. `aws:SourceIp` conditions in bucket policies are unreliable over PrivateLink. Subnet-level network controls (security groups, route tables, NACLs) enforce the actual network boundary - the bucket policy trusts the endpoint identity, not the source IP.

### Pipeline Write Statements (dynamic)
If `pipeline_role_arns` is provided, each role ARN receives a dedicated `Allow` statement for `s3:PutObject`, `s3:DeleteObject`, and `s3:ListBucket`. Pipeline roles do **not** receive the broader management bypass - they are scoped to write operations only.

### Management Access Model

- There is no broad same-account bypass.
- Requests outside the interface endpoint are denied unless the principal ARN matches management patterns derived from `management_principal_arns`.
- Terraform/CI operators that run outside the VPCE path should be listed explicitly in `management_principal_arns` (for example Terragrunt/Terraform execution roles). These principals receive full `s3:*` access.
- Pipeline roles that need bucket writes should be listed in `pipeline_role_arns`; they receive only the dedicated write allow statements and are **not** added to the management bypass.
- The lockout guard (`enforce_deployer_principal_check`) validates the deployer against *both* sets to prevent accidental self-lockout during apply.

---

## DNS and Client Access Guidance

### Private DNS behavior

- Use `vpce_private_dns_enabled` to control whether private DNS is enabled on the S3 interface endpoint.
- Default is `false` for backward compatibility.
- When enabled, VPC resolver behavior can map supported S3 hostnames to endpoint ENIs.
- DNS resolution alone is not sufficient for access. Effective access still depends on network path (subnets, route tables, security groups) and endpoint/bucket policy conditions.

### VPCE DNS name classification

AWS S3 interface endpoints publish multiple DNS names:
- **Regional wildcard**: `*.vpce-{id}-{uniquifier}.s3.{region}.vpce.amazonaws.com` - no AZ suffix, resolves to all endpoint ENIs
- **Zonal wildcards**: `*.vpce-{id}-{uniquifier}-{az}.s3.{region}.vpce.amazonaws.com` - one per AZ, resolves to that AZ's ENI only

The module classifies these automatically by comparing the first DNS label (the `vpce-{id}-{uniquifier}` segment) across all entries. The **shortest** first label belongs to the regional entry; zonal entries extend it with an AZ suffix (`-{az}`). This structural comparison avoids hardcoded label-count assumptions and correctly handles standard regions, GovCloud (`us-gov-west-1a`), and Local Zones (`us-east-1-bos-1a`).

### Bucket host selection algorithm

The `s3_vpce_bucket_host` output selects a single DNS name for the Lambda validation probe and downstream artifact downloads:

1. Filters all DNS names to those matching `vpce-*` (excludes public S3 names).
2. Among VPCE-specific names, selects only wildcards (needed for bucket-style access).
3. Sorts candidates deterministically (by name, stable).
4. Selects the shortest entry (regional names are shorter than zonal, since they lack AZ suffixes).
5. Returns `null` if no real VPCE wildcard names are available - this indicates DNS propagation failure or endpoint misconfiguration and should be treated as a deployment error.

This approach ensures:
- **Deterministic output**: Same infrastructure state always produces the same hostname (no flapping).
- **Regional preference**: The algorithm naturally prefers regional over zonal (shorter string).
- **Real hostname selection**: Uses a name from the AWS Route53 private zone; `null` output is an explicit signal that selection failed rather than a silently non-resolving constructed name.

### Recommended client access pattern

- Use name-based access over endpoint DNS hostnames.
- Do not pin client behavior to endpoint ENI IP addresses.
- Prefer module outputs for host discovery so consumers do not hardcode endpoint DNS assumptions.

### TLS hostname guidance

- Use AWS endpoint-compatible DNS names so TLS hostname verification remains valid.
- Prefer hostnames returned by module outputs (`s3_vpce_bucket_host` and `s3_vpce_validation_hosts`) over custom hostname construction.

### Downstream validation guidance

- Downstream consumers should use `s3_vpce_validation_hosts` as the ordered list of DNS candidates for health checks and download validation.
- Avoid manually constructing `vpce-...` hostnames from endpoint IDs.
- Keep existing compatibility outputs (`s3_vpce_dns_entries`, `s3_vpce_bucket_host`) for legacy workflows, but prefer the explicit regional/zonal and validation-host outputs for new automation.

### Logging bucket post-destroy test guard

The Terratest suite determines whether to assert the logging bucket is deleted after `terraform destroy` using this condition: `loggingBucketName != "" && loggingBucketSSEAlgorithm != ""`. The presence of a non-empty `logging_bucket_sse_algorithm` output is used as a proxy for "module-managed bucket" - an external bucket passed via `logging_target_bucket` does not produce this output, so the test skips the deletion assertion for it. If you point `logging_target_bucket` at an external bucket that was encrypted before use, ensure `logging_bucket_sse_algorithm` returns an empty string to avoid a false post-destroy failure.

---

## Getting Started

Required files and setup:

- **`.golangci.yaml`** - Go linter configuration. This file is tracked in git and required for `make lint` to work. Do not add it to `.gitignore`.
- Run `make configure` to install dependencies and set up pre-commit hooks.
- Run `make lint` to validate the module before testing.

## Testing

- `make test` executes Terraform example planning (`tfmodule/plan`) and then runs functional Go post-deploy tests via `go/test`.
- `make test` currently uses composed double-colon stages in the Makefile, so you will see staged provider generation/planning banners and an additional plan stage in output.
- Post-deploy tests invoke a Lambda function deployed in private subnets to validate S3 endpoint access via network-path-only conditions (no IAM credentials).
- Baseline review target: `examples/complete/test.tfvars` with secure controls enabled.
- Test region defaults are pinned for quota stability: primary deployment in `us-east-2`, replication destination in `us-west-1`.
- `make test` runs end-to-end validation with infrastructure teardown. **Expected duration**: ~35-45 minutes. The test harness runs two sequential `terraform apply` cycles to verify idempotency (`IS_TERRAFORM_IDEMPOTENT_APPLY = true`), which accounts for the majority of the time beyond a single apply+destroy.
- `make go/readonly_test` runs readonly/non-destructive Go verification against existing infrastructure.
- `examples/complete/scaffold.tftest.hcl` runs `terraform test` baseline plan checks. It is not wired into `make test` and does not require deployed infrastructure.
- **Post-destroy verification**: After `terraform destroy`, the Go test suite automatically verifies that the artifacts bucket, disallowed bucket, and Lambda function are actually absent in AWS (`tests/testimpl/test_impl.go: verifyResourcesDestroyed` via `t.Cleanup`).
- **Region drift caution**: Terraform and AWS client environment settings can override region defaults. The Makefile defaults to `us-east-2`, but shell environment variables take precedence. Invoke `make test AWS_REGION=us-east-2` explicitly when validating the baseline profile. A precondition guard in `examples/complete/main.tf` catches provider/variable region mismatches at plan time and aborts early.
- **Common first failure (DNS option mismatch)**: AWS rejects interface endpoint creation when `private_dns_only_for_inbound_resolver_endpoint = true` unless the VPC also has an S3 Gateway endpoint. The baseline `examples/complete/test.tfvars` pins this flag to `false` so `make test` works with the interface-only harness topology.
- **Current validation status**: baseline `terraform apply`/`destroy`, `make test`, `make lint`, focused functional rerun (`go test ./tests/post_deploy_functional -run TestS3BucketCollectionFunctional`), and readonly verification (`go test ./tests/post_deploy_functional_readonly -run TestS3BucketCollectionReadonly`) were run successfully in this PR workflow. GitHub Actions pipeline also passed (full apply/idempotency/destroy cycle).

### Deploy Complete Example And Run Readonly Validation

Use this flow when you want to keep infrastructure deployed and run non-destructive verification.

1. Generate provider files for examples (required because example `provider.tf` files are generated by Makefile workflow and are gitignored):

```bash
make tfmodule/create_example_providers AWS_REGION=us-east-2 AWS_PROFILE=default
```

2. Deploy the complete example and keep it running:

```bash
terraform -chdir=examples/complete init -backend=false
terraform -chdir=examples/complete apply -var-file=test.tfvars
```

3. Run readonly verification against the deployed stack:

```bash
go test -v -count=1 -timeout=2h ./tests/post_deploy_functional_readonly -run TestS3BucketCollectionReadonly
```

Alternative wrapper target:

```bash
make go/readonly_test
```

4. Destroy when finished:

```bash
terraform -chdir=examples/complete destroy -var-file=test.tfvars
```

Operational notes:

- Keep `AWS_REGION=us-east-2` aligned with `examples/complete/test.tfvars` unless you intentionally change the profile.
- Readonly test entrypoint uses `RunNonDestructiveTest` and does not run deploy/destroy stages.

## Baseline Validation Profile

For PR acceptance, baseline validation is centered on `examples/complete/test.tfvars`.

Expected baseline assertions:

- S3 interface endpoint exists and is interface type.
- Artifacts bucket exists with secure transport and endpoint-path controls.
- Lambda network-path validation returns `200/403/403`.
- Bucket encryption state is verified through the S3 API, including effective SSE algorithm and configured CMK ARN when the KMS path is enabled.
- Logging, replication, versioning, and lifecycle controls are configured when enabled in baseline inputs.

Exploratory and degraded profile permutations are intentionally deferred from the default review path and tracked as follow-up work.
Deferred profile variants are tracked as potential future Slice B follow-up work.

## Regula Waiver Rationale (Known Plan-Time Limitations)

This module documents a small set of Regula waiver rationales below for two reasons:

1. Plan-time visibility limits for some S3 checks:
  - `FG_R00100` (HTTPS-only policy)
  - `FG_R00101` (versioning/lifecycle)
  - `FG_R00274` (access logging)
  - `FG_R00275` (replication)

  These controls are implemented in Terraform resources in [main.tf](main.tf), but Regula evaluates Terraform plan JSON. For some resources (notably `aws_s3_bucket_policy`), plan values can be unknown until apply time, so Regula cannot always infer effective bucket behavior from the plan alone.

2. Deferred enhanced audit-event scope:
  - `FG_R00354`
  - `FG_R00355`

  This module covers S3 server access logging. Enhanced access-event telemetry (for example CloudTrail S3 data events) is not included in the current reference-module scope.

Guidance for sync/upstream review:
- Keep waiver rationale documented in inline comments near the relevant S3 policy resources in [main.tf](main.tf) and [examples/complete/main.tf](examples/complete/main.tf).
- Re-evaluate waivers whenever Regula policy behavior or module architecture changes.

### S3 Access Logging

Access logging is **enabled by default** to capture all API calls against the S3 bucket. Logs are written to an auto-created private logging bucket with the `artifact-bucket-logs/` prefix. To use an external logging bucket instead:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution"

  enable_logging        = true
  logging_target_bucket = "my-existing-logging-bucket"
  logging_prefix        = "my-app-logs/"

  # ... other variables
}
```

To disable logging entirely, set `enable_logging = false`.

### Customer-Managed KMS

The module supports opt-in customer-managed KMS keys for each module-managed bucket:

- `artifact_bucket_kms_key_arn`
- `logging_bucket_kms_key_arn`
- `replication_bucket_kms_key_arn`

Important behavior notes:

- `logging_bucket_kms_key_arn` applies only when the module creates the logging bucket. If `logging_target_bucket` points to an external bucket, encryption of that bucket remains the caller's responsibility.
- If `enable_replication = true` and `artifact_bucket_kms_key_arn` is set, you must also set `replication_bucket_kms_key_arn`. The module enforces this because S3 replication of SSE-KMS encrypted objects needs a destination KMS key.
- Enabling a customer-managed KMS key on the artifact bucket changes the consumer access model. The baseline Lambda harness in `examples/complete` intentionally uses unsigned, network-path-only reads; callers that enable artifact-bucket CMKs should expect consumers to use signed S3 requests with KMS authorization.

### Object-Level Replication

Replication to a standby bucket is **enabled by default** and replicates objects and versions to a destination bucket. You can disable it explicitly if not needed:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution"

  enable_replication              = false
  replication_destination_region  = "us-east-1"  # Optional; defaults to primary region

  # ... other variables
}
```

When replication is enabled, it is configured with:
- Real-time replication monitoring (15-minute SLA)
- Versioning always enabled on the destination bucket (hardcoded in the module); the source bucket requires `enable_versioning = true` - the module enforces this at plan time via a `lifecycle.precondition` and will error if you attempt to enable replication without versioning on the source
- Full object tagging and metadata replication
- Output variables expose the destination bucket name and ARN

### Multi-Region Client Access (Redundant VPCE for Replica Bucket)

By default, replication creates a **data-protection copy** in another region - it is not client-accessible via PrivateLink. To make the replica bucket available to clients in the DR region, you need a **second module call** with its own networking stack.

**What's required in the DR region:**
- A VPC with private subnets (same pattern as the primary region)
- Security groups allowing HTTPS (443) inbound from consumer subnets
- Route tables keeping traffic private (no IGW/NAT required for S3 PrivateLink)

**Pattern - two module calls, one per region:**

```hcl
# Primary region - creates artifact bucket + replication + VPCE
module "primary_distribution" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution"

  vpc_id                  = module.primary_vpc.vpc_id
  vpce_subnet_ids         = module.primary_private_subnets[*].subnet_id
  vpce_security_group_ids = [module.primary_vpce_sg.id]
  aws_region              = "us-east-2"

  enable_replication             = true
  replication_destination_region = "us-west-2"

  management_principal_arns = var.management_principal_arns
  pipeline_role_arns        = var.pipeline_role_arns
}

# DR region - creates a second VPCE pointed at the replica bucket
# This makes replicated artifacts readable by clients in the DR region.
module "dr_distribution" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution"
  providers = {
    aws = aws.dr_region
  }

  vpc_id                  = module.dr_vpc.vpc_id
  vpce_subnet_ids         = module.dr_private_subnets[*].subnet_id
  vpce_security_group_ids = [module.dr_vpce_sg.id]
  aws_region              = "us-west-2"

  # The DR instance does NOT create its own artifact bucket or replication -
  # it serves the replica bucket created by the primary module call.
  enable_replication = false
  enable_logging     = true

  # Point the VPCE allowlist at the replica bucket from the primary module
  additional_vpce_allowed_bucket_arns = [module.primary_distribution.replication_bucket_arn]

  management_principal_arns = var.management_principal_arns
}
```

**Key considerations:**
- The DR module call creates its own VPCE and bucket (which may be unused or serve as a warm-standby write target). The critical piece is `additional_vpce_allowed_bucket_arns` pointing to the replica bucket so the VPCE endpoint policy permits reads.
- The replica bucket's policy (created by the primary module) only allows the S3 replication service. You would need to **extend the replica bucket policy** to also allow `s3:GetObject` via the DR-region VPCE - this is not yet automated in the module and would require a policy update outside the primary module call or a future module enhancement.
- Cross-region networking (Transit Gateway, VPC peering) is **not required** for this pattern - each region has its own independent VPCE talking to S3 regional endpoints. The replication is handled server-side by AWS.
- This pattern is currently **not implemented as an example** in this repository due to the additional complexity of managing multi-region provider configurations and the replica bucket policy extension. It is documented here as to provide guidance as to how to make use of this reference module toward that pattern if required.

### Enhanced Audit Events (Out Of Current Scope)

This reference module currently includes S3 server access logging controls only.

If your platform requires enhanced per-object audit telemetry (for example CloudTrail S3 data events), treat that as a separate control outside this module and enforce it through your broader logging architecture and governance standards.

### Lifecycle Management

Lifecycle rules are **enabled by default** to:
- Expire non-current object versions after 90 days (configurable)
- Abort incomplete multipart uploads after 7 days (configurable)

Override these defaults:

```hcl
module "s3_privatelink" {
  source = "git::https://github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution"

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
  source = "git::https://github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution"

  enable_versioning  = false
  enable_replication = false  # required: replication depends on source-bucket versioning

  # ... other variables
}
```

> **Note**: `enable_replication` must also be `false` when `enable_versioning = false`. S3 replication requires versioning on the source bucket. The module enforces this constraint at plan time and will produce an error if you attempt to combine `enable_versioning = false` with `enable_replication = true`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.100, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_artifacts_bucket"></a> [artifacts\_bucket](#module\_artifacts\_bucket) | terraform.registry.launch.nttdata.com/module_collection/s3_bucket/aws | ~> 1.1 |
| <a name="module_logging_bucket"></a> [logging\_bucket](#module\_logging\_bucket) | terraform.registry.launch.nttdata.com/module_collection/s3_bucket/aws | ~> 1.1 |
| <a name="module_s3_interface_vpce"></a> [s3\_interface\_vpce](#module\_s3\_interface\_vpce) | terraform.registry.launch.nttdata.com/module_primitive/vpc_endpoint/aws | ~> 0.1 |
| <a name="module_replication_bucket"></a> [replication\_bucket](#module\_replication\_bucket) | terraform.registry.launch.nttdata.com/module_collection/s3_bucket/aws | ~> 1.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_s3_bucket_logging.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_policy.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_replication_configuration.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_replication_configuration) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [terraform_data.deployer_lockout_guard](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_vpc_endpoint.s3_vpce_refreshed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc_endpoint) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC in which to create the S3 interface endpoint. | `string` | n/a | yes |
| <a name="input_vpce_subnet_ids"></a> [vpce\_subnet\_ids](#input\_vpce\_subnet\_ids) | List of subnet IDs in which to place the endpoint network interfaces. Must be private subnets reachable by artifact consumers. | `list(string)` | n/a | yes |
| <a name="input_vpce_security_group_ids"></a> [vpce\_security\_group\_ids](#input\_vpce\_security\_group\_ids) | Security group IDs to associate with the endpoint ENIs. Must permit inbound HTTPS (443) from consumer CIDRs. | `list(string)` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region where resources are deployed (e.g. us-west-1). Used to construct the S3 endpoint service name. | `string` | n/a | yes |
| <a name="input_vpce_auto_accept"></a> [vpce\_auto\_accept](#input\_vpce\_auto\_accept) | Whether to auto-accept the endpoint request. Typically false unless using a same-account endpoint service pattern. | `bool` | `false` | no |
| <a name="input_vpce_private_dns_enabled"></a> [vpce\_private\_dns\_enabled](#input\_vpce\_private\_dns\_enabled) | Whether to enable private DNS for the S3 interface endpoint in the VPC resolver path. When true, VPC DNS can resolve supported S3 endpoint hostnames to the endpoint ENIs. | `bool` | `false` | no |
| <a name="input_vpce_ip_address_type"></a> [vpce\_ip\_address\_type](#input\_vpce\_ip\_address\_type) | IP address type for the interface endpoint. Valid values: ipv4, dualstack, ipv6. Null uses AWS service default. | `string` | `null` | no |
| <a name="input_vpce_dns_options"></a> [vpce\_dns\_options](#input\_vpce\_dns\_options) | Optional DNS options for the interface endpoint. dns\_record\_ip\_type supports A/AAAA behavior (for example ipv4 or dualstack). | <pre>object({<br/>    dns_record_ip_type                             = optional(string)<br/>    private_dns_only_for_inbound_resolver_endpoint = optional(bool)<br/>  })</pre> | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Base naming prefix applied to all resources created by this module. | `string` | `"msix-s3"` | no |
| <a name="input_additional_vpce_allowed_bucket_arns"></a> [additional\_vpce\_allowed\_bucket\_arns](#input\_additional\_vpce\_allowed\_bucket\_arns) | Optional additional S3 bucket ARNs allowed through the interface endpoint policy. The artifact bucket is always included. | `list(string)` | `[]` | no |
| <a name="input_management_principal_arns"></a> [management\_principal\_arns](#input\_management\_principal\_arns) | Terraform/CI principal ARNs allowed to bypass the VPCE-only deny path. Supports IAM role/user ARNs and STS assumed-role ARNs. Provide explicit trusted principals (for example Terragrunt/Terraform execution role and CI pipeline roles). | `list(string)` | `[]` | no |
| <a name="input_pipeline_role_arns"></a> [pipeline\_role\_arns](#input\_pipeline\_role\_arns) | IAM role ARNs granted write access (PutObject, DeleteObject, ListBucket) to the artifact bucket via dedicated Allow statements. Pipeline roles do NOT receive the broader management bypass (s3:*) - they are scoped to write operations only. Each role generates a distinct policy statement for CloudTrail visibility. | `list(string)` | `[]` | no |
| <a name="input_enforce_deployer_principal_check"></a> [enforce\_deployer\_principal\_check](#input\_enforce\_deployer\_principal\_check) | If true, fail plan/apply unless the current deployment principal ARN resolves to at least one trusted principal in management\_principal\_arns or pipeline\_role\_arns. Prevents accidental Terraform/CI lockout from bucket policy restrictions. | `bool` | `true` | no |
| <a name="input_enable_versioning"></a> [enable\_versioning](#input\_enable\_versioning) | Enable versioning on the S3 artifact bucket. Defaults to true for data protection. | `bool` | `true` | no |
| <a name="input_enable_lifecycle"></a> [enable\_lifecycle](#input\_enable\_lifecycle) | Enable lifecycle rules on the S3 artifact bucket to expire old versions and clean up incomplete multipart uploads. | `bool` | `true` | no |
| <a name="input_lifecycle_noncurrent_version_expiration_days"></a> [lifecycle\_noncurrent\_version\_expiration\_days](#input\_lifecycle\_noncurrent\_version\_expiration\_days) | Number of days after which to expire non-current object versions. Only applies if enable\_lifecycle is true. Set to 0 to disable. | `number` | `90` | no |
| <a name="input_lifecycle_incomplete_multipart_upload_days"></a> [lifecycle\_incomplete\_multipart\_upload\_days](#input\_lifecycle\_incomplete\_multipart\_upload\_days) | Number of days after which to abort incomplete multipart uploads. Only applies if enable\_lifecycle is true. Set to 0 to disable. | `number` | `7` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable S3 access logging for the artifact bucket. If enabled, logs can be sent to an auto-created logging bucket or to an externally-provided bucket. | `bool` | `true` | no |
| <a name="input_logging_target_bucket"></a> [logging\_target\_bucket](#input\_logging\_target\_bucket) | Optional S3 bucket to which access logs should be written. If not provided and enable\_logging is true, a logging bucket will be created automatically. Must already exist and allow the artifact bucket to write logs. | `string` | `null` | no |
| <a name="input_logging_prefix"></a> [logging\_prefix](#input\_logging\_prefix) | Path prefix for access logs written to the logging bucket. Only used if enable\_logging is true. | `string` | `"artifact-bucket-logs/"` | no |
| <a name="input_artifact_bucket_kms_key_arn"></a> [artifact\_bucket\_kms\_key\_arn](#input\_artifact\_bucket\_kms\_key\_arn) | Optional customer-managed KMS key ARN for default encryption on the artifact bucket. Null keeps the module's AES256 default. | `string` | `null` | no |
| <a name="input_logging_bucket_kms_key_arn"></a> [logging\_bucket\_kms\_key\_arn](#input\_logging\_bucket\_kms\_key\_arn) | Optional customer-managed KMS key ARN for the module-managed logging bucket. Null keeps the module's AES256 default. Cannot be used with an external logging\_target\_bucket. | `string` | `null` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Enable S3 replication to a destination bucket in the same or different region. If enabled, a replication destination bucket will be created. | `bool` | `true` | no |
| <a name="input_replication_destination_region"></a> [replication\_destination\_region](#input\_replication\_destination\_region) | AWS region in which to create the replication destination bucket. Only used if enable\_replication is true. If not provided, defaults to the primary region (var.aws\_region). | `string` | `null` | no |
| <a name="input_replication_bucket_kms_key_arn"></a> [replication\_bucket\_kms\_key\_arn](#input\_replication\_bucket\_kms\_key\_arn) | Optional customer-managed KMS key ARN for the replication destination bucket. Null keeps the module's AES256 default. Required when replication is enabled for an artifact bucket that also uses a customer-managed KMS key. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto all taggable resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name (ID) of the S3 artifact bucket. |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 artifact bucket. |
| <a name="output_artifact_bucket_kms_key_arn"></a> [artifact\_bucket\_kms\_key\_arn](#output\_artifact\_bucket\_kms\_key\_arn) | Configured customer-managed KMS key ARN for the artifact bucket. Null means the module is using its AES256 default encryption path. |
| <a name="output_artifact_bucket_sse_algorithm"></a> [artifact\_bucket\_sse\_algorithm](#output\_artifact\_bucket\_sse\_algorithm) | Effective default server-side encryption algorithm for the artifact bucket. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint (e.g. vpce-0abc123). |
| <a name="output_s3_vpce_dns_entries"></a> [s3\_vpce\_dns\_entries](#output\_s3\_vpce\_dns\_entries) | DNS entries for the S3 interface endpoint. Each entry contains dns\_name and hosted\_zone\_id. |
| <a name="output_s3_vpce_private_dns_enabled"></a> [s3\_vpce\_private\_dns\_enabled](#output\_s3\_vpce\_private\_dns\_enabled) | Whether private DNS is enabled for the S3 interface endpoint. |
| <a name="output_s3_vpce_regional_dns_names"></a> [s3\_vpce\_regional\_dns\_names](#output\_s3\_vpce\_regional\_dns\_names) | Regional DNS names discovered from the S3 interface endpoint DNS entries. |
| <a name="output_s3_vpce_zonal_dns_names"></a> [s3\_vpce\_zonal\_dns\_names](#output\_s3\_vpce\_zonal\_dns\_names) | Zonal DNS names discovered from the S3 interface endpoint DNS entries. |
| <a name="output_s3_vpce_bucket_host"></a> [s3\_vpce\_bucket\_host](#output\_s3\_vpce\_bucket\_host) | Resolved bucket-style hostname for the S3 interface endpoint (e.g. bucket.vpce-xxx.s3.us-west-1.vpce.amazonaws.com). Use as the base URL for private artifact downloads. |
| <a name="output_s3_vpce_validation_hosts"></a> [s3\_vpce\_validation\_hosts](#output\_s3\_vpce\_validation\_hosts) | Ordered DNS host candidates for downstream validation. Starts with the preferred regional bucket-style host, followed by zonal and all other endpoint-derived names. |
| <a name="output_logging_bucket_name"></a> [logging\_bucket\_name](#output\_logging\_bucket\_name) | Name of the S3 logging bucket. Returns the auto-created bucket name, the provided external target bucket name, or null when logging is disabled. |
| <a name="output_logging_bucket_arn"></a> [logging\_bucket\_arn](#output\_logging\_bucket\_arn) | ARN of the S3 logging bucket (if created). |
| <a name="output_logging_bucket_kms_key_arn"></a> [logging\_bucket\_kms\_key\_arn](#output\_logging\_bucket\_kms\_key\_arn) | Configured customer-managed KMS key ARN for the module-managed logging bucket. Null means the module is using its AES256 default or the logging bucket is external/unmanaged. |
| <a name="output_logging_bucket_sse_algorithm"></a> [logging\_bucket\_sse\_algorithm](#output\_logging\_bucket\_sse\_algorithm) | Effective default server-side encryption algorithm for the module-managed logging bucket. Returns null when logging is disabled or the logging bucket is external. |
| <a name="output_replication_bucket_name"></a> [replication\_bucket\_name](#output\_replication\_bucket\_name) | Name of the S3 replication destination bucket (if created). Receives replicated objects from the artifact bucket. |
| <a name="output_replication_bucket_arn"></a> [replication\_bucket\_arn](#output\_replication\_bucket\_arn) | ARN of the S3 replication destination bucket (if created). |
| <a name="output_replication_bucket_kms_key_arn"></a> [replication\_bucket\_kms\_key\_arn](#output\_replication\_bucket\_kms\_key\_arn) | Configured customer-managed KMS key ARN for the replication destination bucket. Null means the module is using its AES256 default or replication is disabled. |
| <a name="output_replication_bucket_sse_algorithm"></a> [replication\_bucket\_sse\_algorithm](#output\_replication\_bucket\_sse\_algorithm) | Effective default server-side encryption algorithm for the replication destination bucket. Returns null when replication is disabled. |
<!-- END_TF_DOCS -->
