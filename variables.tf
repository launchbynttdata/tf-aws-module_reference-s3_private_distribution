# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Required - networking context provided by the caller
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the VPC in which to create the S3 interface endpoint."
  type        = string
  nullable    = false
}

variable "vpce_subnet_ids" {
  description = "List of subnet IDs in which to place the endpoint network interfaces. Must be private subnets reachable by artifact consumers."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.vpce_subnet_ids) > 0
    error_message = "At least one subnet ID must be provided for the S3 interface endpoint."
  }
}

variable "vpce_security_group_ids" {
  description = "Security group IDs to associate with the endpoint ENIs. Must permit inbound HTTPS (443) from consumer CIDRs."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.vpce_security_group_ids) > 0
    error_message = "At least one security group ID must be provided for the S3 interface endpoint."
  }
}

# ---------------------------------------------------------------------------
# Required - region (drives service name construction)
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region where resources are deployed (e.g. us-west-1). Used to construct the S3 endpoint service name."
  type        = string
  nullable    = false
}

# ---------------------------------------------------------------------------
# Optional - endpoint behavior tuning (pass-through to primitive module)
# ---------------------------------------------------------------------------

variable "vpce_auto_accept" {
  description = "Whether to auto-accept the endpoint request. Typically false unless using a same-account endpoint service pattern."
  type        = bool
  default     = false
}

variable "vpce_private_dns_enabled" {
  description = "Whether to enable private DNS for the S3 interface endpoint in the VPC resolver path. When true, VPC DNS can resolve supported S3 endpoint hostnames to the endpoint ENIs."
  type        = bool
  default     = false
}

variable "vpce_ip_address_type" {
  description = "IP address type for the interface endpoint. Valid values: ipv4, dualstack, ipv6. Null uses AWS service default."
  type        = string
  default     = null

  validation {
    condition     = var.vpce_ip_address_type == null ? true : contains(["ipv4", "dualstack", "ipv6"], var.vpce_ip_address_type)
    error_message = "vpce_ip_address_type must be one of: ipv4, dualstack, ipv6, or null."
  }
}

variable "vpce_dns_options" {
  description = "Optional DNS options for the interface endpoint. dns_record_ip_type supports A/AAAA behavior (for example ipv4 or dualstack)."
  type = object({
    dns_record_ip_type                             = optional(string)
    private_dns_only_for_inbound_resolver_endpoint = optional(bool)
  })
  default = null
}

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------

variable "name_prefix" {
  description = "Base naming prefix applied to all resources created by this module."
  type        = string
  default     = "msix-s3"
}

# ---------------------------------------------------------------------------
# Access policy - S3 endpoint policy
# ---------------------------------------------------------------------------

variable "additional_vpce_allowed_bucket_arns" {
  description = "Optional additional S3 bucket ARNs allowed through the interface endpoint policy. The artifact bucket is always included."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Access policy - S3 bucket policy principals
# ---------------------------------------------------------------------------

variable "management_principal_arns" {
  description = "Terraform/CI principal ARNs allowed to bypass the VPCE-only deny path. Supports IAM role/user ARNs and STS assumed-role ARNs. Provide explicit trusted principals (for example Terragrunt/Terraform execution role and CI pipeline roles)."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.management_principal_arns :
      can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{0,12}:.+$", arn))
    ])
    error_message = "All management_principal_arns entries must be valid AWS ARNs."
  }
}

variable "pipeline_role_arns" {
  description = "IAM role ARNs granted write access (PutObject, DeleteObject, ListBucket) to the artifact bucket via dedicated Allow statements. Pipeline roles do NOT receive the broader management bypass (s3:*) - they are scoped to write operations only. Each role generates a distinct policy statement for CloudTrail visibility."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.pipeline_role_arns :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", arn))
    ])
    error_message = "All pipeline_role_arns entries must be IAM role ARNs in the format arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME."
  }
}

variable "enforce_deployer_principal_check" {
  description = "If true, fail plan/apply unless the current deployment principal ARN resolves to at least one trusted principal in management_principal_arns or pipeline_role_arns. Prevents accidental Terraform/CI lockout from bucket policy restrictions."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Lifecycle Management
# ---------------------------------------------------------------------------

variable "enable_versioning" {
  description = "Enable versioning on the S3 artifact bucket. Defaults to true for data protection."
  type        = bool
  default     = true
}

variable "enable_lifecycle" {
  description = "Enable lifecycle rules on the S3 artifact bucket to expire old versions and clean up incomplete multipart uploads."
  type        = bool
  default     = true
}

variable "lifecycle_noncurrent_version_expiration_days" {
  description = "Number of days after which to expire non-current object versions. Only applies if enable_lifecycle is true. Set to 0 to disable."
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_noncurrent_version_expiration_days >= 0
    error_message = "Must be >= 0. Use 0 to disable expiration of old versions."
  }
}

variable "lifecycle_incomplete_multipart_upload_days" {
  description = "Number of days after which to abort incomplete multipart uploads. Only applies if enable_lifecycle is true. Set to 0 to disable."
  type        = number
  default     = 7

  validation {
    condition     = var.lifecycle_incomplete_multipart_upload_days >= 0
    error_message = "Must be >= 0. Use 0 to disable cleanup of incomplete uploads."
  }
}

# ---------------------------------------------------------------------------
# Access Logging
# ---------------------------------------------------------------------------

variable "enable_logging" {
  description = "Enable S3 access logging for the artifact bucket. If enabled, logs can be sent to an auto-created logging bucket or to an externally-provided bucket."
  type        = bool
  default     = true
}

variable "logging_target_bucket" {
  description = "Optional S3 bucket to which access logs should be written. If not provided and enable_logging is true, a logging bucket will be created automatically. Must already exist and allow the artifact bucket to write logs."
  type        = string
  default     = null
}

variable "logging_prefix" {
  description = "Path prefix for access logs written to the logging bucket. Only used if enable_logging is true."
  type        = string
  default     = "artifact-bucket-logs/"
}

variable "artifact_bucket_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for default encryption on the artifact bucket. Null keeps the module's AES256 default."
  type        = string
  default     = null

  validation {
    condition     = var.artifact_bucket_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.artifact_bucket_kms_key_arn))
    error_message = "artifact_bucket_kms_key_arn must be a valid AWS KMS key ARN or null."
  }
}

variable "logging_bucket_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for the module-managed logging bucket. Null keeps the module's AES256 default. Cannot be used with an external logging_target_bucket."
  type        = string
  default     = null

  validation {
    condition     = var.logging_bucket_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.logging_bucket_kms_key_arn))
    error_message = "logging_bucket_kms_key_arn must be a valid AWS KMS key ARN or null."
  }

  validation {
    condition     = !(!var.enable_logging && var.logging_bucket_kms_key_arn != null)
    error_message = "logging_bucket_kms_key_arn can only be set when enable_logging is true."
  }

  validation {
    condition     = !(var.logging_target_bucket != null && var.logging_bucket_kms_key_arn != null)
    error_message = "logging_bucket_kms_key_arn applies only to the module-managed logging bucket. Omit it when logging_target_bucket points to an external bucket."
  }
}

# ---------------------------------------------------------------------------
# Replication
# ---------------------------------------------------------------------------

variable "enable_replication" {
  description = "Enable S3 replication to a destination bucket in the same or different region. If enabled, a replication destination bucket will be created."
  type        = bool
  default     = true
}

variable "replication_destination_region" {
  description = "AWS region in which to create the replication destination bucket. Only used if enable_replication is true. If not provided, defaults to the primary region (var.aws_region)."
  type        = string
  default     = null
}

variable "replication_bucket_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for the replication destination bucket. Null keeps the module's AES256 default. Required when replication is enabled for an artifact bucket that also uses a customer-managed KMS key."
  type        = string
  default     = null

  validation {
    condition     = var.replication_bucket_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.replication_bucket_kms_key_arn))
    error_message = "replication_bucket_kms_key_arn must be a valid AWS KMS key ARN or null."
  }

  validation {
    condition     = !(!var.enable_replication && var.replication_bucket_kms_key_arn != null)
    error_message = "replication_bucket_kms_key_arn can only be set when enable_replication is true."
  }

  validation {
    condition     = !(var.enable_replication && var.artifact_bucket_kms_key_arn != null && var.replication_bucket_kms_key_arn == null)
    error_message = "replication_bucket_kms_key_arn must be set when enable_replication is true and artifact_bucket_kms_key_arn is configured, because SSE-KMS replication requires a destination KMS key."
  }
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto all taggable resources."
  type        = map(string)
  default     = {}
}
