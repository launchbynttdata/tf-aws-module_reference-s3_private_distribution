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

output "s3_bucket_name" {
  description = "Name (ID) of the S3 artifact bucket."
  value       = module.artifacts_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 artifact bucket."
  value       = module.artifacts_bucket.arn
}

output "s3_interface_vpce_id" {
  description = "ID of the S3 interface VPC endpoint (e.g. vpce-0abc123)."
  value       = module.s3_interface_vpce.id
}

output "s3_vpce_dns_entries" {
  description = "DNS entries for the S3 interface endpoint. Each entry contains dns_name and hosted_zone_id."
  value       = module.s3_interface_vpce.dns_entry
}

output "s3_vpce_bucket_host" {
  description = "Resolved bucket-style hostname for the S3 interface endpoint (e.g. bucket.vpce-xxx.s3.us-west-1.vpce.amazonaws.com). Use as the base URL for private artifact downloads."
  value       = local.s3_vpce_bucket_host
}

output "logging_bucket_name" {
  description = "Name of the S3 logging bucket. Returns the auto-created bucket name, the provided external target bucket name, or null when logging is disabled."
  value       = var.enable_logging ? (var.logging_target_bucket != null ? var.logging_target_bucket : module.logging_bucket[0].id) : null
}

output "logging_bucket_arn" {
  description = "ARN of the S3 logging bucket (if created)."
  value       = var.enable_logging && var.logging_target_bucket == null ? module.logging_bucket[0].arn : null
}

output "replication_bucket_name" {
  description = "Name of the S3 replication destination bucket (if created). Receives replicated objects from the artifact bucket."
  value       = var.enable_replication ? module.replication_bucket[0].id : null
}

output "replication_bucket_arn" {
  description = "ARN of the S3 replication destination bucket (if created)."
  value       = var.enable_replication ? module.replication_bucket[0].arn : null
}

output "replication_bucket_private_base_url" {
  description = "Bucket base URL for private access to the replication bucket over the S3 interface endpoint hostname."
  value       = var.enable_replication ? "https://${local.s3_vpce_bucket_host}/${module.replication_bucket[0].id}" : null
}
