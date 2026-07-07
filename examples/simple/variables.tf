variable "aws_region" {
  description = "AWS region for test deployment."
  type        = string
  default     = "us-west-1"
}

variable "name_prefix" {
  description = "Base naming prefix for harness and module resources."
  type        = string
  default     = "msix-s3-simple"
}

variable "management_principal_arns" {
  description = "Optional management principal ARNs for the module. If empty, the example falls back to the current execution principal ARN."
  type        = list(string)
  default     = []
}

variable "pipeline_role_arns" {
  description = "Optional pipeline role ARNs granted write access by the module."
  type        = list(string)
  default     = []
}

variable "vpce_private_dns_enabled" {
  description = "Whether to enable private DNS for the S3 interface endpoint in this example."
  type        = bool
  default     = false
}

variable "enable_replication" {
  description = "Enable replication in the root module. Defaults to false in this simple example to keep rollout/testing output focused on management principal behavior."
  type        = bool
  default     = false
}
