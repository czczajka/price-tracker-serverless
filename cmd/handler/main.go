package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/go-echarts/go-echarts/v2/charts"
	"github.com/go-echarts/go-echarts/v2/opts"
	plotTypes "github.com/go-echarts/go-echarts/v2/types"
)

type MyEvent struct {
	Name  string  `json:"name"`
	Date  string  `json:"date"`
	Value float32 `json:"value"`
}

type Entry struct {
	Date  string  `json:"date"`
	Value float32 `json:"value"`
}

//go:embed app.config
var configFS embed.FS

type AppConfig struct {
	AppBucket string `json:"appBucket"`
}

// Function responsible for handling result returned from tracker lambda
// Main steps which function is repsonsile for:
// 1. Create dynamo db table if not exists
// 1. Put received event into dynamo table
// 2. Generate plot for item and upload it to S3
func HandleRequest(ctx context.Context, event json.RawMessage) error {
	fmt.Print("Handler Lambda \n")
	fmt.Printf("Request payload: %v\n", string(event))

	var awsCfg AppConfig
	configFile, err := configFS.ReadFile("app.config")
	if err != nil {
		return fmt.Errorf("failed to read config file: %w", err)
	}

	err = json.Unmarshal(configFile, &awsCfg)
	if err != nil {
		return fmt.Errorf("failed to parse config file: %w", err)
	}

	// Use the configuration in your application
	fmt.Printf("App Bucket: %s\n", awsCfg.AppBucket)

	// Get request payload and parse it to MyEvent struct
	var result map[string]interface{}
	if err := json.Unmarshal([]byte(event), &result); err != nil {
		return fmt.Errorf("Error parsing JSON: %v", err)
	}

	responsePayload, ok := result["responsePayload"]
	if !ok {
		return fmt.Errorf("error field not found")
	}

	fieldJSON, err := json.Marshal(responsePayload)
	if err != nil {
		return fmt.Errorf("Error marshaling field to JSON: %v", err)
	}

	var myEvent MyEvent
	if err := json.Unmarshal(fieldJSON, &myEvent); err != nil {
		return fmt.Errorf("Error parsing myEvent: %v", err)
	}

	fmt.Printf("Event data: %v\n", myEvent)

	// Create dynamo db client
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("failed to load configuration, %v", err)
	}

	dbClient := dynamodb.NewFromConfig(cfg)

	// Create dynamo db table
	// For testing purposes there will be n attempts to create table each time
	_, err = dbClient.CreateTable(ctx, &dynamodb.CreateTableInput{
		TableName: aws.String(myEvent.Name),
		AttributeDefinitions: []types.AttributeDefinition{
			{
				AttributeName: aws.String("date"),
				AttributeType: types.ScalarAttributeTypeS,
			},
		},
		KeySchema: []types.KeySchemaElement{
			{
				AttributeName: aws.String("date"),
				KeyType:       types.KeyTypeHash,
			},
		},
		BillingMode: types.BillingModePayPerRequest,
	})
	if err != nil {
		var resourceInUseException *types.ResourceInUseException
		if ok := errors.As(err, &resourceInUseException); ok {
			fmt.Printf("Table already exists\n")
		} else {
			return fmt.Errorf("failed to create table: %w", err)
		}
	}

	// Put item into dynamo db
	_, err = dbClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(myEvent.Name),
		Item: map[string]types.AttributeValue{
			"date":  &types.AttributeValueMemberS{Value: myEvent.Date},
			"value": &types.AttributeValueMemberN{Value: fmt.Sprintf("%f", myEvent.Value)},
		},
	})
	if err != nil {
		return fmt.Errorf("failed to put item into table: %w", err)
	}

	// New plots generation
	// Get all items from dynamo db
	dbRsp, err := dbClient.Scan(ctx, &dynamodb.ScanInput{
		TableName: aws.String(myEvent.Name),
	})
	if err != nil {
		return fmt.Errorf("failed to scan table: %w", err)
	}

	items := dbRsp.Items
	var entries []Entry
	// Convert dynamo data to models.Entry
	for _, item := range items {
		fmt.Printf("Item in db: %s\n", item)
		var date, value string
		if val, ok := item["date"].(*types.AttributeValueMemberS); ok {
			date = val.Value
		} else {
			return fmt.Errorf("failed to get data from dynamo table: %w", err)
		}
		if val, ok := item["value"].(*types.AttributeValueMemberN); ok {
			value = val.Value
		} else {
			return fmt.Errorf("failed to get data from dynamo table: %w", err)
		}
		fmt.Printf("Read from db: %s  %s\n", date, value)

		valNumeric, err := strconv.ParseFloat(value, 32)
		if err != nil {
			return fmt.Errorf("failed to convert string to float: %w", err)
		}

		entry := Entry{
			Date:  date,
			Value: float32(valNumeric),
		}
		entries = append(entries, entry)
	}

	sorted := sortEntries(entries)

	// Create s3 session where plots will be uploaded
	s3Client := s3.NewFromConfig(cfg)

	buf, err := generatePlot(sorted)
	if err != nil {
		fmt.Printf("Error generating plot: %v\n", err)
		return fmt.Errorf("failed to generate plot: %w", err)
	}

	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(awsCfg.AppBucket),
		Key:         aws.String(myEvent.Name + ".html"),
		Body:        bytes.NewReader(buf),
		ContentType: aws.String("text/html"),
	})
	if err != nil {
		fmt.Printf("Error uploading file to S3: %v\n", err)
		return fmt.Errorf("failed to upload file to S3: %v", err)
	}

	fmt.Print("GenPlots completed successfully")

	// Return the JSON as a string
	return nil
}

func main() {
	lambda.Start(HandleRequest)
}

func generateLineItems(entries []Entry) []opts.LineData {
	items := make([]opts.LineData, 0)
	for _, entry := range entries {
		items = append(items, opts.LineData{Value: entry.Value})
	}
	return items
}

// Html file with a plot will be created in destinationDir
func generatePlot(entries []Entry) ([]byte, error) {
	line := charts.NewLine()
	// set some global options like Title/Legend/ToolTip or anything else
	line.SetGlobalOptions(
		charts.WithInitializationOpts(opts.Initialization{Width: "1200px", Height: "350px", Theme: plotTypes.ThemeChalk}))

	var dateLabels []string
	for _, entry := range entries {
		dateLabels = append(dateLabels, entry.Date)
	}

	var buf bytes.Buffer

	// Put data into instance
	line.SetXAxis(dateLabels).
		AddSeries("Price", generateLineItems(entries)).
		SetSeriesOptions(charts.WithLineChartOpts(opts.LineChart{Smooth: false}))

	err := line.Render(&buf)
	if err != nil {
		fmt.Printf("Error rendering plot: %v\n", err)
		return []byte{}, fmt.Errorf("failed to render plot: %w", err)
	}
	return buf.Bytes(), nil
}

// SortEntries sorts a slice of Entry by date and time in ascending order.
func sortEntries(entries []Entry) []Entry {
	sortedEntries := make([]Entry, len(entries))
	copy(sortedEntries, entries)

	dateFormat := "2006-01-02T15:04"

	sort.Slice(sortedEntries, func(i, j int) bool {
		t1, err1 := time.Parse(dateFormat, sortedEntries[i].Date)
		t2, err2 := time.Parse(dateFormat, sortedEntries[j].Date)
		if err1 != nil || err2 != nil {
			fmt.Printf("Error parsing date: %v, %v\n", err1, err2)
			return false
		}
		return t1.Before(t2)
	})

	return sortedEntries
}

// TODO - creation of table take time, you need to wait until table is created
// Now it's a chance taht first item will be not added to table because it's not created yet
// For demo purposes it's ok, but in production it should be fixed
