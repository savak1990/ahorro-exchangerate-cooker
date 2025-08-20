# Local variables
locals {
  db_name     = "${var.base_name}-db"
  lambda_name = "${var.base_name}-lambda"
}

# Data source to get the Lambda zip from S3
data "aws_s3_object" "lambda_zip" {
  bucket = var.app_s3_bucket_name
  key    = var.app_s3_artifact_zip_key
}

# DynamoDB table for exchange rates
resource "aws_dynamodb_table" "exchange_rate_db" {
  name         = local.db_name
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "Key"
    type = "S"
  }

  attribute {
    name = "SortKey"
    type = "S"
  }

  hash_key  = "Key"
  range_key = "SortKey"
}

# Lambda function
resource "aws_lambda_function" "exchange_rate_cooker" {
  function_name     = local.lambda_name
  role              = aws_iam_role.lambda_role.arn
  handler           = "bootstrap"
  runtime           = "provided.al2"
  s3_bucket         = var.app_s3_bucket_name
  s3_key            = var.app_s3_artifact_zip_key
  s3_object_version = data.aws_s3_object.lambda_zip.version_id
  source_code_hash  = data.aws_s3_object.lambda_zip.etag
  timeout           = 300

  environment {
    variables = {
      EXCHANGE_RATE_DB_NAME = aws_dynamodb_table.exchange_rate_db.name
      EXCHANGE_RATE_API_KEY = var.exchange_rate_api_key
      SUPPORTED_CURRENCIES  = join("|", var.supported_currencies)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${local.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

# IAM policy attachment for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${local.lambda_name}-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
        ]
        Resource = aws_dynamodb_table.exchange_rate_db.arn
      }
    ]
  })
}

# EventBridge rule for scheduled execution
resource "aws_cloudwatch_event_rule" "exchange_rate_schedule" {
  name                = "${local.lambda_name}-schedule"
  description         = "Trigger exchange rate cooker"
  schedule_expression = var.schedule_expression
}

# EventBridge target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.exchange_rate_schedule.name
  target_id = "ExchangeRateCookerTarget"
  arn       = aws_lambda_function.exchange_rate_cooker.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.exchange_rate_cooker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.exchange_rate_schedule.arn
}
