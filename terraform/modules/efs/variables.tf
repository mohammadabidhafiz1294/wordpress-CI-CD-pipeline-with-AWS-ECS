variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access EFS"
  type        = list(string)
}

variable "kms_key_id" {
  description = "KMS key ID for EFS encryption (optional)"
  type        = string
  default     = ""
}
