variable "base_name" {
  description = "Base name for all resources"
  type        = string
}

variable "app_s3_bucket_name" {
  description = "S3 bucket name where Lambda deployment package is stored"
  type        = string
}

variable "app_s3_artifact_zip_key" {
  description = "S3 key for Lambda deployment package"
  type        = string
}

variable "exchange_rate_api_key" {
  description = "API key for exchange rate service"
  type        = string
  default     = ""
  sensitive   = true
}

variable "schedule_expression" {
  description = "Schedule expression for EventBridge rule (cron format)"
  type        = string
  default     = "cron(10 0 * * ? *)" # Once a day at 00:10 UTC
}

variable "supported_currencies" {
  description = "List of supported currencies"
  type        = list(string)
  default     = ["USD", "JPY", "CAD", "AUD", "CNY", "EUR", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "UAH", "BYN", "RUB"]
}

variable "ttl_interval_days" {
  description = "Time to live (TTL) interval in days"
  type        = number
  default     = 30
}
