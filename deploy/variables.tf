variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "ahorro"
}

variable "component_name" {
  description = "Name of the service"
  type        = string
  default     = "exchange-rate"
}

variable "env" {
  description = "Deployment environment"
  type        = string
  default     = "stable"
}
