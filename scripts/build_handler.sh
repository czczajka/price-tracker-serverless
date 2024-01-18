#!/bin/bash

GOOS=linux GOARCH=amd64 go build -o dist/handler/main cmd/handler/main.go

pushd dist/handler
zip main.zip main
popd