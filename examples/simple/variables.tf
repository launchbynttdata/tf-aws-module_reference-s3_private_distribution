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
