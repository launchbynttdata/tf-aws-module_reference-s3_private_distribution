# ---------------------------------------------------------------------------
# Region and naming
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for test deployment."
  type        = string
  default     = "us-west-1"
}

variable "name_prefix" {
  description = "Base naming prefix for all harness and module resources."
  type        = string
  default     = "msix-s3-complete"
}

# ---------------------------------------------------------------------------
# Harness networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the test VPC."
  type        = string
  default     = "10.48.0.0/16"
}

variable "app_private_subnet_cidrs" {
  description = "CIDRs for private app subnets (one per AZ; receive S3/SSM endpoint ENIs)."
  type        = list(string)
  default     = ["10.48.10.0/24", "10.48.11.0/24"]
}

variable "client_subnet_cidr" {
  description = "CIDR for the single-AZ client emulator subnet."
  type        = string
  default     = "10.48.20.0/24"
}

# ---------------------------------------------------------------------------
# Windows client emulator
# ---------------------------------------------------------------------------

variable "windows_instance_type" {
  description = "EC2 instance type for the Windows client emulator."
  type        = string
  default     = "t3.large"
}

variable "windows_key_name" {
  description = "Optional EC2 key pair for the Windows instance. Leave null for SSM-only access."
  type        = string
  default     = null
}

variable "admin_ingress_cidrs" {
  description = "Optional CIDR blocks for RDP (3389) ingress to the Windows emulator. Empty list keeps RDP closed."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Collection module — policy inputs
# (these are passed through to the s3-bucket collection module)
# ---------------------------------------------------------------------------

variable "pipeline_role_arns" {
  description = "IAM role ARNs granted write access to the artifact bucket (passed to collection module)."
  type        = list(string)
  default     = []
}

variable "additional_vpce_allowed_bucket_arns" {
  description = "Additional S3 bucket ARNs allowed through the endpoint policy (passed to collection module)."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Collection module — feature toggles
# (these are passed through to the collection module)
# ---------------------------------------------------------------------------

variable "enable_versioning" {
  description = "Pass-through: enable versioning on the collection module artifact bucket."
  type        = bool
  default     = true
}

variable "enable_lifecycle" {
  description = "Pass-through: enable lifecycle rules on the collection module artifact bucket."
  type        = bool
  default     = true
}

variable "lifecycle_noncurrent_version_expiration_days" {
  description = "Pass-through: non-current object expiration days for lifecycle rules."
  type        = number
  default     = 90
}

variable "lifecycle_incomplete_multipart_upload_days" {
  description = "Pass-through: days to abort incomplete multipart uploads."
  type        = number
  default     = 7
}

variable "enable_logging" {
  description = "Pass-through: enable S3 access logging behavior in the collection module."
  type        = bool
  default     = true
}

variable "logging_target_bucket" {
  description = "Pass-through: optional external logging target bucket. If null, module-managed logging bucket is used when logging is enabled."
  type        = string
  default     = null
}

variable "logging_prefix" {
  description = "Pass-through: prefix for S3 access logs."
  type        = string
  default     = "artifact-bucket-logs/"
}

variable "enable_replication" {
  description = "Pass-through: enable replication behavior in the collection module."
  type        = bool
  default     = true
}

variable "replication_destination_region" {
  description = "Pass-through: optional destination region for replication bucket creation."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
