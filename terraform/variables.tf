variable "region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-east-2"
}

variable "name" {
  description = "Prefix for resource names"
  type        = string
  default     = "cdl"
}