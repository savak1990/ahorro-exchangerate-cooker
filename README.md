# Ahorro Exchange Rate Cooker

A serverless application that fetches and stores exchange rates in DynamoDB on a scheduled basis using AWS Lambda and EventBridge.

## Architecture

- **AWS Lambda**: Go-based function that fetches exchange rates from an external API
- **DynamoDB**: Stores exchange rates with TTL for automatic expiration
- **EventBridge**: Triggers the Lambda function on a configurable schedule (default: once per day)
- **Terraform**: Infrastructure as Code for deployment

## Project Structure

```
├── app/                    # Lambda function source code
│   ├── main.go            # Main Lambda handler
│   └── go.mod             # Go module dependencies
├── terraform/             # Terraform modules
│   ├── main.tf           # Main module configuration
│   ├── variables.tf      # Module variables
│   ├── output.tf         # Module outputs
│   └── database/         # DynamoDB module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── deploy/               # Deployment configuration
│   ├── main.tf          # Main deployment
│   ├── variables.tf     # Deployment variables
│   └── outputs.tf       # Deployment outputs
├── build/               # Build artifacts (created by make build)
├── Makefile            # Build and deployment automation
└── README.md           # This file
```

## Prerequisites

- Go 1.21 or later
- Terraform 1.0 or later
- AWS CLI configured with appropriate credentials
- Make utility

## Quick Start

1. **Build the Lambda function:**
   ```bash
   make build
   ```

2. **Package for deployment:**
   ```bash
   make package
   ```

3. **Deploy infrastructure:**
   ```bash
   make deploy
   ```

## Configuration

The following variables can be configured in `deploy/variables.tf` or passed during deployment:

- `base_name`: Base name for all resources (default: "ahorro")
- `environment`: Environment name (default: "dev")
- `exchange_rate_api_key`: API key for exchange rate service (optional)
- `schedule_expression`: EventBridge schedule expression (default: "rate(1 day)")

### Schedule Expression Examples

- `rate(1 day)` - Once per day
- `rate(12 hours)` - Every 12 hours
- `rate(30 minutes)` - Every 30 minutes
- `cron(0 0 * * ? *)` - Daily at midnight UTC
- `cron(0 12 * * ? *)` - Daily at noon UTC

## Make Targets

- `make build` - Build the Lambda binary
- `make package` - Package the Lambda for deployment
- `make deploy` - Deploy using Terraform (init, plan, apply)
- `make clean` - Clean build artifacts
- `make test` - Run tests
- `make fmt` - Format Go code
- `make deps` - Download Go dependencies
- `make init` - Initialize Terraform
- `make plan` - Plan Terraform changes
- `make apply` - Apply Terraform changes
- `make destroy` - Destroy infrastructure
- `make help` - Show available targets

## Lambda Function

The Lambda function is written in Go and uses AWS SDK v2. It:

1. Fetches exchange rates from an external API
2. Stores the rates in DynamoDB with automatic expiration (TTL)
3. Logs the operation for monitoring

### Environment Variables

The Lambda function uses these environment variables:

- `EXCHANGE_RATE_DB_NAME`: DynamoDB table name
- `EXCHANGE_RATE_API_KEY`: API key for the exchange rate service (optional)

## DynamoDB Schema

The DynamoDB table stores exchange rates with the following structure:

- `ToCurrency` (String, Hash Key): The target currency code (e.g., "USD", "EUR")
- `Rate` (Number): The exchange rate value
- `Date` (String): The date when the rate was fetched
- `ExpiresAt` (Number): Unix timestamp for TTL expiration
- `UpdatedAt` (String): Timestamp when the record was last updated

## Monitoring

- CloudWatch Logs: Lambda function logs are stored in `/aws/lambda/{function-name}`
- CloudWatch Metrics: Standard Lambda metrics are available
- EventBridge: Rule execution can be monitored in the EventBridge console

## Development

1. **Install dependencies:**
   ```bash
   make deps
   ```

2. **Format code:**
   ```bash
   make fmt
   ```

3. **Run tests:**
   ```bash
   make test
   ```

4. **Build locally:**
   ```bash
   make build
   ```

## Cleanup

To remove all AWS resources:

```bash
make destroy
```

## License

This project is part of the Ahorro application suite.