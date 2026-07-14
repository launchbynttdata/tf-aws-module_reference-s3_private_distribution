# Simple Example

This example demonstrates a minimal harness for invoking the private
S3 distribution reference module from the repository root.

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

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_s3_privatelink"></a> [s3\_privatelink](#module\_s3\_privatelink) | ../.. | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_default_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_security_group.vpce](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_role.current_assumed_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for test deployment. | `string` | `"us-west-1"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Base naming prefix for harness and module resources. | `string` | `"msix-s3-simple"` | no |
| <a name="input_management_principal_arns"></a> [management\_principal\_arns](#input\_management\_principal\_arns) | Optional management principal ARNs for the module. If empty, the example falls back to the current execution principal ARN. | `list(string)` | `[]` | no |
| <a name="input_pipeline_role_arns"></a> [pipeline\_role\_arns](#input\_pipeline\_role\_arns) | Optional pipeline role ARNs granted write access by the module. | `list(string)` | `[]` | no |
| <a name="input_vpce_private_dns_enabled"></a> [vpce\_private\_dns\_enabled](#input\_vpce\_private\_dns\_enabled) | Whether to enable private DNS for the S3 interface endpoint in this example. | `bool` | `false` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Enable replication in the root module. Defaults to false in this simple example to keep rollout/testing output focused on management principal behavior. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 artifact bucket created by the reference module. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint. |
| <a name="output_s3_vpce_bucket_host"></a> [s3\_vpce\_bucket\_host](#output\_s3\_vpce\_bucket\_host) | Bucket-style hostname for the interface endpoint. |
| <a name="output_s3_vpce_regional_dns_names"></a> [s3\_vpce\_regional\_dns\_names](#output\_s3\_vpce\_regional\_dns\_names) | Regional DNS names discovered from the S3 interface endpoint DNS entries. |
| <a name="output_s3_vpce_zonal_dns_names"></a> [s3\_vpce\_zonal\_dns\_names](#output\_s3\_vpce\_zonal\_dns\_names) | Zonal DNS names discovered from the S3 interface endpoint DNS entries. |
| <a name="output_s3_vpce_validation_hosts"></a> [s3\_vpce\_validation\_hosts](#output\_s3\_vpce\_validation\_hosts) | Ordered DNS host candidates for downstream validation. Starts with the preferred regional bucket-style host, followed by zonal and all other endpoint-derived names. |
<!-- END_TF_DOCS -->
