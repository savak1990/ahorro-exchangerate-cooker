provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "ahorro-app"
      Service     = "ahorro-exchangerate-cooker"
      Terraform   = "true"
    }
  }
}

data "aws_secretsmanager_secret" "ahorro_app" {
  name = local.secret_name
}

data "aws_secretsmanager_secret_version" "ahorro_app" {
  secret_id = data.aws_secretsmanager_secret.ahorro_app.id
}

# Local variables
locals {
  base_name   = "${var.app_name}-${var.component_name}-${var.env}"
  secret_name = "${var.app_name}-app-secrets"

  # S3 configuration for Lambda package
  s3_bucket_name = "ahorro-artifacts"
  s3_key         = "${var.component_name}/${var.env}/exchangerate-lambda.zip"
}

# Main exchange rate cooker module
module "exchange_rate_cooker" {
  source = "../terraform"

  base_name               = local.base_name
  app_s3_bucket_name      = local.s3_bucket_name
  app_s3_artifact_zip_key = local.s3_key
  exchange_rate_api_key   = jsondecode(data.aws_secretsmanager_secret_version.ahorro_app.secret_string)["exchange_rate_api_key"]
  schedule_expression     = "cron(10 0 * * ? *)" // Once a day at 00:10 UTC
  supported_currencies    = ["USD", "JPY", "CAD", "AUD", "CNY", "EUR", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "UAH", "BYN", "RUB"]
}

terraform {
  backend "s3" {
    bucket = "ahorro-app-state"
    ### Please update "savak" to your user name if you're going to try deploying this yourself
    key            = "dev/ahorro-exchangerate-cooker/savak/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "ahorro-app-state-lock"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
