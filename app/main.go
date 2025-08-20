package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/sirupsen/logrus"
)

type ExchangeRateResponse struct {
	Result          string             `json:"result"`
	BaseCode        string             `json:"base_code"`
	ConversionRates map[string]float64 `json:"conversion_rates"`
}

type ExchangeRateRecord struct {
	Key           string             `dynamodbav:"Key"`
	SortKey       string             `dynamodbav:"SortKey"`
	ExchangeRates map[string]float64 `dynamodbav:"ExchangeRates"`
	UpdatedAt     time.Time          `dynamodbav:"UpdatedAt"`
}

type SupportedCurrenciesRecord struct {
	Key                 string    `dynamodbav:"Key"`
	SortKey             string    `dynamodbav:"SortKey"`
	SupportedCurrencies []string  `dynamodbav:"SupportedCurrencies"`
	UpdatedAt           time.Time `dynamodbav:"UpdatedAt"`
}

var (
	dynamoClient        *dynamodb.Client
	tableName           string
	apiKey              string
	supportedCurrencies []string
)

func init() {
	// Configure logrus
	logrus.SetFormatter(&logrus.JSONFormatter{})

	// Set log level from environment variable
	logLevel := os.Getenv("LOG_LEVEL")
	switch strings.ToLower(logLevel) {
	case "debug":
		logrus.SetLevel(logrus.DebugLevel)
	case "info":
		logrus.SetLevel(logrus.InfoLevel)
	case "warn", "warning":
		logrus.SetLevel(logrus.WarnLevel)
	case "error":
		logrus.SetLevel(logrus.ErrorLevel)
	default:
		logrus.SetLevel(logrus.InfoLevel) // Default to info
	}

	logrus.WithField("log_level", logrus.GetLevel().String()).Info("Logger configured")

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		logrus.WithError(err).Fatal("unable to load SDK config")
	}

	dynamoClient = dynamodb.NewFromConfig(cfg)
	tableName = os.Getenv("EXCHANGE_RATE_DB_NAME")
	apiKey = os.Getenv("EXCHANGE_RATE_API_KEY")

	// Parse supported currencies from environment variable
	supportedCurrenciesStr := os.Getenv("SUPPORTED_CURRENCIES")
	if supportedCurrenciesStr != "" {
		supportedCurrencies = strings.Split(supportedCurrenciesStr, "|")
	} else {
		// Default currencies if not specified
		supportedCurrencies = []string{"EUR", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "UAH", "BYN", "RUB"}
	}

	if tableName == "" {
		logrus.Fatal("EXCHANGE_RATE_DB_NAME environment variable is required")
	}

	logrus.WithFields(logrus.Fields{
		"table_name":           tableName,
		"supported_currencies": supportedCurrencies,
		"currencies_count":     len(supportedCurrencies),
		"api_key_configured":   apiKey != "",
	}).Info("Exchange rate cooker initialized")
}

func handler(ctx context.Context, event events.CloudWatchEvent) error {
	startTime := time.Now()
	logrus.WithFields(logrus.Fields{
		"event_time":   time.Now().Format(time.RFC3339),
		"event_source": event.Source,
		"event_id":     event.ID,
	}).Info("Exchange rate cooker triggered")

	// Get current date for storing
	currentDate := time.Now().Format("2006-01-02")
	logrus.WithField("date", currentDate).Debug("Processing date set")

	// Store supported currencies configuration
	if err := storeSupportedCurrencies(); err != nil {
		logrus.WithError(err).Error("Failed to store supported currencies configuration")
		// Log error but continue with processing - this is not critical
	} else {
		logrus.Info("Successfully stored supported currencies configuration")
	}

	successCount := 0
	errorCount := 0
	skippedCount := 0

	// Process each supported currency
	for i, baseCurrency := range supportedCurrencies {
		logger := logrus.WithFields(logrus.Fields{
			"currency":       baseCurrency,
			"currency_index": i + 1,
			"total_count":    len(supportedCurrencies),
		})

		logger.Info("Processing exchange rates for currency")

		// First, check if data already exists for this currency and date
		existingRecord, err := checkExistingExchangeRates(baseCurrency, currentDate)
		if err != nil {
			logger.WithError(err).Error("Failed to check existing exchange rates")
			errorCount++
			continue
		}

		if existingRecord != nil {
			logger.WithFields(logrus.Fields{
				"existing_rates_count": len(existingRecord.ExchangeRates),
				"updated_at":           existingRecord.UpdatedAt.Format(time.RFC3339),
			}).Info("Exchange rates already exist for this currency and date, skipping API call")
			skippedCount++
			continue
		}

		logger.Info("No existing data found, fetching from API")

		// Fetch exchange rates from API
		rates, err := fetchExchangeRates(baseCurrency)
		if err != nil {
			logger.WithError(err).Error("Failed to fetch exchange rates")
			errorCount++
			continue // Continue with next currency instead of failing completely
		}

		logger.WithField("rates_count", len(rates.ConversionRates)).Debug("Exchange rates fetched successfully")

		// Store rates in DynamoDB
		err = storeExchangeRates(baseCurrency, currentDate, rates)
		if err != nil {
			logger.WithError(err).Error("Failed to store exchange rates")
			errorCount++
			continue
		}

		logger.WithField("rates_count", len(rates.ConversionRates)).Info("Successfully updated exchange rates for currency")
		successCount++
	}

	duration := time.Since(startTime)
	logrus.WithFields(logrus.Fields{
		"total_currencies": len(supportedCurrencies),
		"success_count":    successCount,
		"error_count":      errorCount,
		"skipped_count":    skippedCount,
		"duration_ms":      duration.Milliseconds(),
	}).Info("Exchange rate update completed")

	if errorCount > 0 && successCount == 0 && skippedCount == 0 {
		return fmt.Errorf("all currency updates failed: %d errors", errorCount)
	}

	return nil
}

func fetchExchangeRates(baseCurrency string) (*ExchangeRateResponse, error) {
	// Validate baseCurrency
	if len(baseCurrency) != 3 {
		return nil, fmt.Errorf("baseCurrency must be 3 characters")
	}
	for _, r := range baseCurrency {
		if r < 'A' || r > 'Z' {
			return nil, fmt.Errorf("baseCurrency must be uppercase letters")
		}
	}

	var url string
	if apiKey != "" {
		url = fmt.Sprintf("https://v6.exchangerate-api.com/v6/%s/latest/%s", apiKey, baseCurrency)
	} else {
		url = fmt.Sprintf("https://api.exchangerate-api.com/v4/latest/%s", baseCurrency)
	}

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch exchange rates: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d", resp.StatusCode)
	}

	var exchangeRates ExchangeRateResponse
	if err := json.NewDecoder(resp.Body).Decode(&exchangeRates); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	// Check if the API call was successful (for the paid API version)
	if exchangeRates.Result != "" && exchangeRates.Result != "success" {
		return nil, fmt.Errorf("API call failed with result: %s", exchangeRates.Result)
	}

	return &exchangeRates, nil
}

func checkExistingExchangeRates(baseCurrency, date string) (*ExchangeRateRecord, error) {
	key := map[string]interface{}{
		"Key":     baseCurrency,
		"SortKey": date,
	}

	keyItem, err := attributevalue.MarshalMap(key)
	if err != nil {
		return nil, fmt.Errorf("error marshaling key for %s: %w", baseCurrency, err)
	}

	result, err := dynamoClient.GetItem(context.TODO(), &dynamodb.GetItemInput{
		TableName: aws.String(tableName),
		Key:       keyItem,
	})

	if err != nil {
		return nil, fmt.Errorf("error checking existing rates for %s on %s: %w", baseCurrency, date, err)
	}

	// If no item found, return nil (no error)
	if result.Item == nil {
		return nil, nil
	}

	var record ExchangeRateRecord
	err = attributevalue.UnmarshalMap(result.Item, &record)
	if err != nil {
		return nil, fmt.Errorf("error unmarshaling existing record for %s: %w", baseCurrency, err)
	}

	return &record, nil
}

func storeExchangeRates(baseCurrency, date string, rates *ExchangeRateResponse) error {
	record := ExchangeRateRecord{
		Key:           baseCurrency,
		SortKey:       date,
		ExchangeRates: rates.ConversionRates,
		UpdatedAt:     time.Now(),
	}

	item, err := attributevalue.MarshalMap(record)
	if err != nil {
		return fmt.Errorf("error marshaling record for %s: %w", baseCurrency, err)
	}

	_, err = dynamoClient.PutItem(context.TODO(), &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})
	if err != nil {
		return fmt.Errorf("error storing rates for %s: %w", baseCurrency, err)
	}

	logrus.WithFields(logrus.Fields{
		"currency":    baseCurrency,
		"date":        date,
		"rates_count": len(rates.ConversionRates),
		"table":       tableName,
	}).Debug("Successfully stored exchange rates to DynamoDB")
	return nil
}

func storeSupportedCurrencies() error {
	record := SupportedCurrenciesRecord{
		Key:                 "SupportedCurrencies",
		SortKey:             "-",
		SupportedCurrencies: supportedCurrencies,
		UpdatedAt:           time.Now(),
	}

	item, err := attributevalue.MarshalMap(record)
	if err != nil {
		return fmt.Errorf("error marshaling supported currencies record: %w", err)
	}

	_, err = dynamoClient.PutItem(context.TODO(), &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})
	if err != nil {
		return fmt.Errorf("error storing supported currencies: %w", err)
	}

	logrus.WithFields(logrus.Fields{
		"supported_currencies": supportedCurrencies,
		"currencies_count":     len(supportedCurrencies),
		"table":                tableName,
	}).Debug("Successfully stored supported currencies to DynamoDB")
	return nil
}

func main() {
	lambda.Start(handler)
}
