# with_cake

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cake_prefix"></a> [cake\_prefix](#module\_cake\_prefix) | ../.. | n/a |
| <a name="module_cake_suffix"></a> [cake\_suffix](#module\_cake\_suffix) | ../.. | n/a |

## Resources

| Name | Type |
|------|------|
| [random_integer.cake_pos](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/integer) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_length"></a> [length](#input\_length) | n/a | `number` | `24` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_string"></a> [string](#output\_string) | n/a |
<!-- END_TF_DOCS -->
