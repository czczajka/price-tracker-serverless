package main

import (
	"context"
	"embed"
	"fmt"
	"html/template"
	"log"
	"net/http"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/sirupsen/logrus"
)

var plotsBucket = "price-tracker-plots"

//go:embed templates/home.page.tmpl
var tmpl embed.FS

func homeHandler(w http.ResponseWriter, r *http.Request) {
	t, err := template.ParseFS(tmpl, "templates/home.page.tmpl")
	if err != nil {
		panic(err)
	}

	// Connect to s3
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		fmt.Printf("failed to load configuration, %v", err)
		return
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
		Bucket: &plotsBucket,
	})
	if err != nil {
		fmt.Printf("Unable to list items in bucket %q, %v", plotsBucket, err)
		return
	}

	fmt.Println("Objects in S3 Bucket:")
	for _, item := range resp.Contents {
		fmt.Printf("* %s\n", *item.Key)
	}
	for _, item := range resp.Contents {
		item := Item{
			Path: fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", plotsBucket, cfg.Region, *item.Key),
			Name: *item.Key,
		}
		logrus.Infof("Item from S3: %v", item)
		data.Items = append(data.Items, item)
	}

	fmt.Println(data)

	// Execute the template with some data
	err = t.Execute(w, data)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
	return
}

func main() {
	http.HandleFunc("/", homeHandler)

	fmt.Printf("Starting server at port :80")
	if err := http.ListenAndServe(":80", nil); err != nil {
		log.Fatal(err)
	}

	// t, err := template.ParseFS(tmpl, "templates/home.page.tmpl")
	// if err != nil {
	// 	panic(err)
	// }

	// Connect to s3
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	// if err != nil {
	// 	return fmt.Errorf("failed to load configuration, %v", err)
	// }
	s3Client := s3.NewFromConfig(cfg)

	type Item struct {
		Path string
		Name string
	}

	data := struct {
		Items []Item
	}{}

	// Get all items from s3 bucket
	bucket := "price-tracker-plots"

	// List objects
	resp, err := s3Client.ListObjectsV2(context.TODO(), &s3.ListObjectsV2Input{
		Bucket: &bucket,
	})
	if err != nil {
		log.Fatalf("Unable to list items in bucket %q, %v", bucket, err)
	}

	fmt.Println("Objects in S3 Bucket:")
	for _, item := range resp.Contents {
		fmt.Printf("* %s\n", *item.Key)
	}
	for _, item := range resp.Contents {
		item := Item{
			Path: fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", bucket, cfg.Region, *item.Key),
			Name: *item.Key,
		}
		logrus.Infof("Item from S3: %v", item)
		data.Items = append(data.Items, item)
	}

	fmt.Println(data)
	// Execute the template with some data
	// err = t.Execute(w, data)
	// if err != nil {
	// 	http.Error(w, err.Error(), http.StatusInternalServerError)
	// }
}
