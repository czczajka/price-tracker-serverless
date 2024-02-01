#!/bin/bash

set -e

export AWS_PAGER=""

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

LAMBDA_TRACKER=tracker-exampleItem
LAMBDA_HANDLER=tracker-handler
LAMBDA_GATEWAY=tracker-gateway
BUCKET_NAME=`jq -r '.appBucket' app.config`

# Create a public bucket
aws s3 mb s3://${BUCKET_NAME} 

aws s3api put-public-access-block \
    --bucket ${BUCKET_NAME}  \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Make the bucket public
aws s3api put-bucket-policy \
    --bucket ${BUCKET_NAME}  \
    --policy file://policy/s3bucket-public.json

# Create necessary policies
# Create tracker-policy
aws iam create-policy \
    --policy-name tracker-policy \
    --policy-document file://policy/tracker-policy.json

# Create handler-policy
aws iam create-policy \
    --policy-name handler-policy \
    --policy-document file://policy/handler-policy.json

# Create gateway-policy
aws iam create-policy \
    --policy-name gateway-policy \
    --policy-document file://policy/gateway-policy.json

# Create necessary roles
# Create tracker-role
aws iam create-role \
    --role-name tracker-role \
    --assume-role-policy-document file://role/lambda-role.json

# Attach tracker-policy to tracker-role
aws iam attach-role-policy \
    --role-name tracker-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/tracker-policy"

# Create handler-role
aws iam create-role \
    --role-name handler-role \
    --assume-role-policy-document file://role/lambda-role.json

# Attach handler-policy to handler-role
aws iam attach-role-policy \
    --role-name handler-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/handler-policy"

# Create gateway-role
aws iam create-role \
    --role-name gateway-role \
    --assume-role-policy-document file://role/lambda-role.json

# Attach gateway-policy to gateway-role
aws iam attach-role-policy \
    --role-name gateway-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/gateway-policy"

# Create a new tracker lambda function
./scripts/build_tracker_lambda.sh
aws lambda create-function \
    --function-name ${LAMBDA_TRACKER} \
    --runtime python3.9 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/tracker-role" \
    --handler "app.lambda_handler" \
    --zip-file "fileb://dist/example_tracker/main.zip"


# Create a new handler lambda function
./scripts/build_go_lambdas.sh
aws lambda create-function \
    --function-name ${LAMBDA_HANDLER} \
    --runtime go1.x \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/handler-role" \
    --handler "main" \
    --zip-file "fileb://dist/handler/main.zip"

# Add handler lambda as destinator for tracker lambda
aws lambda put-function-event-invoke-config \
    --function-name ${LAMBDA_TRACKER} \
    --destination-config '{"OnSuccess":{"Destination":"arn:aws:lambda:us-east-1:'${AWS_ACCOUNT_ID}':function:'${LAMBDA_HANDLER}'"}}'

# Create a new rule to invoke the tracker lambda function every 2 minutes
aws events put-rule \
    --name ${LAMBDA_TRACKER} \
    --schedule-expression 'rate(2 minutes)'

# Add the rule as an event source for the tracker lambda function
aws lambda add-permission \
    --function-name ${LAMBDA_TRACKER} \
    --statement-id eventbridge-invoke \
    --action 'lambda:InvokeFunction' \
    --principal events.amazonaws.com \
    --source-arn 'arn:aws:events:us-east-1:'${AWS_ACCOUNT_ID}':rule/'${LAMBDA_TRACKER}''

aws events put-targets \
    --rule ${LAMBDA_TRACKER} \
    --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:${LAMBDA_TRACKER}"

# Create a lambda, which is connected with api gateway
aws lambda create-function \
    --function-name "tracker-gateway" \
    --runtime go1.x \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/gateway-role" \
    --handler "main" \
    --zip-file "fileb://dist/gateway/main.zip"

# Create a new api gateway and connect to / endpoint with the gateway lambda function
aws apigatewayv2 create-api \
    --name "${LAMBDA_GATEWAY}" \
    --protocol-type HTTP \
    --target "arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:${LAMBDA_GATEWAY}"

GATEWAY_ID=`aws apigatewayv2 get-apis | jq -r '.Items[] | select(.Name=="'${LAMBDA_GATEWAY}'") | .ApiId'`
echo "Gateway ID: ${GATEWAY_ID}"

# Create a GET route for the api gateway
aws apigatewayv2 create-route \
    --api-id "${GATEWAY_ID}" \
    --route-key "GET /"

# Get route id
ROUTE_ID=`aws apigatewayv2 get-routes --api-id "${GATEWAY_ID}" | jq -r '.Items[] | select(.RouteKey=="GET /") | .RouteId'`
echo "Route ID: ${ROUTE_ID}"

# Get integration id
INTEGRATION_ID=`aws apigatewayv2 get-integrations --api-id "${GATEWAY_ID}"  | jq -r '.Items[] | .IntegrationId'`
echo "Integration ID: ${INTEGRATION_ID}"

# Update the route to use the integration
aws apigatewayv2 update-route \
    --api-id "${GATEWAY_ID}" \
    --route-id "${ROUTE_ID}" \
    --target "integrations/${INTEGRATION_ID}"


aws lambda add-permission \
 --statement-id 5a6058ce-ce87-5bde-ab73-ea5adca00378 \
 --action lambda:InvokeFunction \
 --function-name "arn:aws:lambda:us-east-1:680401233849:function:${LAMBDA_GATEWAY}" \
 --principal apigateway.amazonaws.com \
 --source-arn "arn:aws:execute-api:us-east-1:680401233849:${GATEWAY_ID}/*/*/"

# Get the api gateway url
URL=`aws apigatewayv2 get-apis | jq -r '.Items[] | select(.Name=="'${LAMBDA_GATEWAY}'") | .ApiEndpoint'`
echo "URL: ${URL}"

# TODO in future Create policies, roles in script
# Use app.config to store the common names