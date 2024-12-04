variable "region" {
  default = "us-west-1"
}

variable "backend_image" {
  default = "backend:latest"
}

variable "frontend_image" {
  default = "frontend:latest"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-1b", "us-west-1c"]
}

variable "db_username" {
  description = "Database master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}
variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
}