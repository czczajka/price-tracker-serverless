#!/bin/bash

GOOS=linux GOARCH=amd64 go build -o dist/gateway/main cmd/gateway/main.go

pushd dist/gateway
zip main.zip main
popd