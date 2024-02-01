#!/bin/bash

ROOT_DIR=$(pwd)
PROJECT_NAME=example_tracker


pushd lambdas/trackers/item
mkdir -p ${ROOT_DIR}/dist/$PROJECT_NAME
zip ${ROOT_DIR}/dist/$PROJECT_NAME/main.zip app.py
popd