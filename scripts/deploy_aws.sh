#!/bin/bash

export AWS_PAGER=""

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

LAMBDA_TRACKER=tracker-exampleItem
LAMBDA_HANDLER=tracker-handler
LAMBDA_GATEWAY=tracker-gateway

./scripts/build_example_tracker.sh
# Create a new tracker lambda function
aws lambda create-function \
    --function-name ${LAMBDA_TRACKER} \
    --runtime python3.9 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/tracker-role" \
    --handler "app.handler" \
    --zip-file "fileb://dist/example_tracker/main.zip"


# Build go apps
./scripts/build_go_apps_with_docker.sh
# Create a new handler lambda function
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