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
# Required — networking context provided by the caller
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
# Required — region (drives service name construction)
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region where resources are deployed (e.g. us-west-1). Used to construct the S3 endpoint service name."
  type        = string
  nullable    = false
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
# Access policy — S3 endpoint policy
# ---------------------------------------------------------------------------

variable "additional_vpce_allowed_bucket_arns" {
  description = "Optional additional S3 bucket ARNs allowed through the interface endpoint policy. The artifact bucket is always included."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Access policy — S3 bucket policy principals
# ---------------------------------------------------------------------------

variable "management_principal_arns" {
  description = "Additional principal ARNs (IAM roles, users) to exempt from the VPCE-only read restriction. The caller identity is always included. Accepts both arn:aws:iam:: and arn:aws:sts:: formats; STS assumed-role wildcard patterns are generated automatically."
  type        = list(string)
  default     = []
}

variable "pipeline_role_arns" {
  description = "IAM role ARNs granted write access (PutObject, DeleteObject, ListBucket) to the artifact bucket. Each generates a distinct Allow statement so the access is visible in CloudTrail."
  type        = list(string)
  default     = []
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

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto all taggable resources."
  type        = map(string)
  default     = {}
}
