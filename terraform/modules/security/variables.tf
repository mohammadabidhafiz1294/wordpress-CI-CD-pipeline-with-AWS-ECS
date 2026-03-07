variable "vpc_id" {
  description = "ID of VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of VPC"
  type        = string
  default     = "11.0.0.0/16"
}
