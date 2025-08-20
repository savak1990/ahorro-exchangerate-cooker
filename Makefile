# Basic arguments
APP_NAME=ahorro
COMPONENT_NAME=exchangerate
INSTANCE_NAME=$(shell whoami)
AWS_REGION=eu-west-1

FULL_NAME=$(APP_NAME)-$(COMPONENT_NAME)-$(INSTANCE_NAME)

# Main app arguments
APP_DIR=app
APP_BUILD_DIR=./build
APP_LAMBDA_ZIP_BASE_NAME=$(COMPONENT_NAME)-lambda
APP_LAMBDA_ZIP_NAME=$(APP_LAMBDA_ZIP_BASE_NAME).zip
APP_LAMBDA_HANDLER_ZIP=$(APP_BUILD_DIR)/$(APP_LAMBDA_ZIP_NAME)
APP_LAMBDA_BINARY=$(APP_BUILD_DIR)/bootstrap

# S3 paths for different deployment types
APP_LAMBDA_S3_BASE=s3://ahorro-artifacts/$(COMPONENT_NAME)
APP_LAMBDA_S3_PATH_LOCAL=$(APP_LAMBDA_S3_BASE)/$(INSTANCE_NAME)/$(APP_LAMBDA_ZIP_NAME)

.PHONY: all build package test clean deploy undeploy plan upload help

# Default target
all: build

# Build the Lambda binary using Docker (ensures compatibility)
$(APP_LAMBDA_BINARY): $(shell find $(APP_DIR) -type f -name '*.go')
	@echo "Building Lambda binary using Docker (ensures compatibility)..."
	@mkdir -p $(APP_BUILD_DIR)
	@docker run \
		-v $(PWD)/$(APP_DIR):/src \
		-v $(PWD)/$(APP_BUILD_DIR):/build \
		-v $(PWD)/.git:/src/.git \
		-w /src \
		golang:1.23-alpine \
		sh -c "apk add --no-cache git ca-certificates && \
		       go mod tidy && \
		       CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		       go build -ldflags='-s -w -extldflags=-static' -tags netgo -a \
		       -o /build/bootstrap main.go"

# Package the Lambda for deployment
$(APP_LAMBDA_HANDLER_ZIP): $(APP_LAMBDA_BINARY)
	@mkdir -p $(APP_BUILD_DIR)
	cd $(APP_BUILD_DIR) && zip $(APP_LAMBDA_ZIP_NAME) bootstrap

# Combined build and package targets
build: $(APP_LAMBDA_BINARY)

package: $(APP_LAMBDA_HANDLER_ZIP)

# Upload targets
upload: $(APP_LAMBDA_HANDLER_ZIP)
	@echo "Uploading Lambda package to: $(APP_LAMBDA_S3_PATH_LOCAL)"
	aws s3 rm $(APP_LAMBDA_S3_PATH_LOCAL) --quiet || true
	aws s3 cp $(APP_LAMBDA_HANDLER_ZIP) $(APP_LAMBDA_S3_PATH_LOCAL)

# Terraform deployment helpers
plan:
	cd deploy && \
	terraform init && \
	terraform plan \
		-var="app_name=$(APP_NAME)" \
		-var="component_name=$(COMPONENT_NAME)" \
		-var="env=$(INSTANCE_NAME)"

refresh:
	cd deploy && \
	terraform init && \
	terraform refresh \
		-var="app_name=$(APP_NAME)" \
		-var="component_name=$(COMPONENT_NAME)" \
		-var="env=$(INSTANCE_NAME)"

# Use this only for development purposes
deploy:
	@echo "Deploying the exchange rate cooker service..."
	cd deploy && \
	terraform init && \
	terraform apply -auto-approve \
		-var="app_name=$(APP_NAME)" \
		-var="component_name=$(COMPONENT_NAME)" \
		-var="env=$(INSTANCE_NAME)"

undeploy:
	@echo "Undeploying the exchange rate cooker service..."
	cd deploy && \
	terraform init && \
	terraform destroy -auto-approve \
		-var="app_name=$(APP_NAME)" \
		-var="component_name=$(COMPONENT_NAME)" \
		-var="env=$(INSTANCE_NAME)"

# Test and clean targets
test:
	@echo "Running tests..."
	cd $(APP_DIR) && go test -v ./...

clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(APP_BUILD_DIR) .timestamp
	@echo "Clean complete"

# Format Go code
fmt:
	@echo "Formatting Go code..."
	cd $(APP_DIR) && go fmt ./...

# Download Go dependencies
deps:
	@echo "Downloading dependencies..."
	cd $(APP_DIR) && go mod download
	cd $(APP_DIR) && go mod tidy

# Help target
help:
	@echo "Ahorro Exchange Rate Cooker - Available Makefile targets:"
	@echo ""
	@echo "📦 Build & Package:"
	@echo "  build                 - Build Lambda binary using Docker"
	@echo "  package               - Create Lambda deployment package"
	@echo ""
	@echo "🧪 Testing:"
	@echo "  test                  - Run Go tests"
	@echo "  clean                 - Clean build artifacts"
	@echo "  fmt                   - Format Go code"
	@echo "  deps                  - Download Go dependencies"
	@echo ""
	@echo "📤 Upload:"
	@echo "  upload                - Upload Lambda package to S3 (s3://ahorro-artifacts/exchangerate/\$INSTANCE_NAME/)"
	@echo ""
	@echo "🚀 Deployment:"
	@echo "  deploy                - Deploy infrastructure and service"
	@echo "  undeploy              - Destroy infrastructure"
	@echo "  plan                  - Show Terraform plan"
	@echo ""
	@echo "🔧 Utilities:"
	@echo "  help                  - Show this help message"
	@echo ""
	@echo "💡 Examples:"
	@echo "  # Build and upload:"
	@echo "  make build && make upload"
	@echo ""
	@echo "  # Deploy:"
	@echo "  make package && make deploy"
