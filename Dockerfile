# Start from the official Golang image
FROM golang:latest as builder

# Set the working directory inside the container
WORKDIR /app

# Install zip
RUN apt-get update && apt-get install -y zip

# Copy the Go Modules manifests and download modules
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code into the container
COPY . .

# Build each application
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/handler/main ./cmd/handler/main.go
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/gateway/main ./cmd/gateway/main.go

RUN zip -j handler.zip dist/handler/main
RUN zip -j gateway.zip dist/gateway/main

# Final stage: Create a smaller image without Go installed
FROM alpine:latest  
RUN apk --no-cache add ca-certificates
WORKDIR /root/

# Copy the binaries from the builder stage
COPY --from=builder /app/handler.zip .
COPY --from=builder /app/gateway.zip .

# No CMD or ENTRYPOINT as this image is not intended to be run
