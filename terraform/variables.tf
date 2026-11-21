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

variable "enable_guardduty" {
  description = "Turn GuardDuty on (starts the 30-day free trial)"
  type        = bool
  default     = false
}