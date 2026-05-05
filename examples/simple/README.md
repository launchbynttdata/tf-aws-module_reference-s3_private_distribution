# Simple Example

This example demonstrates minimal invocation of the portable s3-bucket package.

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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_s3_privatelink"></a> [s3\_privatelink](#module\_s3\_privatelink) | ../.. | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_default_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_security_group.vpce](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for test deployment. | `string` | `"us-west-1"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Base naming prefix for harness and module resources. | `string` | `"msix-s3-simple"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 artifact bucket created by the collection module. |
| <a name="output_s3_interface_vpce_id"></a> [s3\_interface\_vpce\_id](#output\_s3\_interface\_vpce\_id) | ID of the S3 interface VPC endpoint. |
| <a name="output_s3_vpce_bucket_host"></a> [s3\_vpce\_bucket\_host](#output\_s3\_vpce\_bucket\_host) | Bucket-style hostname for the interface endpoint. |
<!-- END_TF_DOCS -->
