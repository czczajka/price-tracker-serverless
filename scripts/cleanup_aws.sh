#!/bin/bash

LAMBDA_TRACKER=tracker-exampleItem
LAMBDA_HANDLER=tracker-handler
LAMBDA_GATEWAY=tracker-gateway

# Delete the tracker lambda function
aws lambda delete-function \
    --function-name ${LAMBDA_TRACKER}

# Delete the handler lambda function
aws lambda delete-function \
    --function-name ${LAMBDA_HANDLER}

# Rule remove targets
aws events remove-targets \
    --rule ${LAMBDA_TRACKER} \
    --ids 1

# Delete the rule
aws events delete-rule \
    --name ${LAMBDA_TRACKER}

# Delete the gateway lambda function
aws lambda delete-function \
    --function-name ${LAMBDA_GATEWAY}

# Delete the api gateway
GATEWAY_ID=`aws apigatewayv2 get-apis | jq -r '.Items[] | select(.Name=="'${LAMBDA_GATEWAY}'") | .ApiId'`

aws apigatewayv2 delete-api \
    --api-id ${GATEWAY_ID}