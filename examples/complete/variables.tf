variable "aws_region" {
  description = "AWS region for resource deployment."
  type        = string
  default     = "us-east-2"
}

variable "vpce_auto_accept" {
  description = "Whether to auto-accept the interface endpoint request."
  type        = bool
  default     = false
}

variable "vpce_ip_address_type" {
  description = "IP address type for the interface endpoint (ipv4, dualstack, ipv6). Null uses service default."
  type        = string
  default     = null
}

variable "vpce_dns_options" {
  description = "Optional DNS behavior for the interface endpoint."
  type = object({
    dns_record_ip_type                             = optional(string)
    private_dns_only_for_inbound_resolver_endpoint = optional(bool)
  })
  default = null
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "launch-s3probe"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "lambda_runtime" {
  description = "Lambda runtime for the validation function."
  type        = string
  default     = "python3.12"
}

# S3 Module Variables
variable "management_principal_arns" {
  description = "Explicit Terraform/CI principal ARNs allowed to bypass VPCE-only restrictions."
  type        = list(string)
  default     = []
}

variable "pipeline_role_arns" {
  description = "ARNs of pipeline roles allowed to access the bucket."
  type        = list(string)
  default     = []
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket."
  type        = bool
  default     = false
}

variable "enable_lifecycle" {
  description = "Enable lifecycle rules on the bucket."
  type        = bool
  default     = true
}

variable "lifecycle_noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent versions before expiration."
  type        = number
  default     = 30
}

variable "lifecycle_incomplete_multipart_upload_days" {
  description = "Days to retain incomplete multipart uploads."
  type        = number
  default     = 7
}

variable "enable_logging" {
  description = "Enable S3 access logging."
  type        = bool
  default     = false
}

variable "logging_target_bucket" {
  description = "Target bucket for access logs. Mutually exclusive with use_external_logging_target."
  type        = string
  default     = null
}

variable "use_external_logging_target" {
  description = "When true, routes S3 access logs to the self-managed external logging target bucket created by this example (named <name_prefix>-ext-log) instead of the auto-created logging bucket inside the root module."
  type        = bool
  default     = false
}

variable "logging_prefix" {
  description = "Prefix for access logs."
  type        = string
  default     = "logs/"
}

variable "enable_replication" {
  description = "Enable cross-region replication."
  type        = bool
  default     = false
}

variable "replication_destination_region" {
  description = "Destination region for replication."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default = {
    Terraform = "true"
    Purpose   = "S3-PrivateLink-Validation"
  }
}
