output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.exchange_rate_cooker.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.exchange_rate_cooker.lambda_function_arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.exchange_rate_cooker.dynamodb_table_name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = module.exchange_rate_cooker.dynamodb_table_arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = module.exchange_rate_cooker.eventbridge_rule_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = module.exchange_rate_cooker.eventbridge_rule_arn
}
