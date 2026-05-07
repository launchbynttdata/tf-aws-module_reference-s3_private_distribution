variable "aws_region" {
  description = "AWS region for resource deployment."
  type        = string
  default     = "us-east-1"
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
  description = "ARNs of principals allowed to manage the S3 bucket."
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
  description = "Target bucket for access logs."
  type        = string
  default     = null
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
