package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/sirupsen/logrus"
)

//go:embed templates/home.page.tmpl
var tmpl embed.FS

//go:embed app.config
var configFS embed.FS

type AppConfig struct {
	AppBucket string `json:"appBucket"`
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	fmt.Print("Home Lambda \n")

	var awsCfg AppConfig
	configFile, err := configFS.ReadFile("app.config")
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       "Error reading config file",
		}, err
	}

	err = json.Unmarshal(configFile, &awsCfg)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       "Error parsing config file",
		}, err
	}

	// Use the configuration in your application
	fmt.Printf("App Bucket: %s", awsCfg.AppBucket)

	t, err := template.ParseFS(tmpl, "templates/home.page.tmpl")
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       "Error parsing template",
		}, err
	}

	// Connect to s3
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       "Error loading config",
		}, err
	}
	s3Client := s3.NewFromConfig(cfg)

	type Item struct {
		Path string
		Name string
	}

	data := struct {
		Items []Item
	}{}

	// Get all items from s3 bucket
	// List objects
	resp, err := s3Client.ListObjectsV2(context.TODO(), &s3.ListObjectsV2Input{
		Bucket: &awsCfg.AppBucket,
	})
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       "Error listing objects",
		}, err
	}

	fmt.Println("Objects in S3 Bucket:")
	for _, item := range resp.Contents {
		fmt.Printf("* %s\n", *item.Key)
	}
	for _, item := range resp.Contents {
		item := Item{
			Path: fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", awsCfg.AppBucket, cfg.Region, *item.Key),
			Name: *item.Key,
		}
		logrus.Infof("Item from S3: %v", item)
		data.Items = append(data.Items, item)
	}

	fmt.Println(data)

	// Execute the template with some data
	var buf bytes.Buffer
	err = t.Execute(&buf, data)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       "Error executing template",
		}, err
	}
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers:    map[string]string{"Content-Type": "text/html"},
		Body:       buf.String(),
	}, nil
}

func main() {
	lambda.Start(handleRequest)
}
