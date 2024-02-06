#!/bin/bash

#set -x

export AWS_PAGER=""

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

LAMBDA_TRACKER=tracker-exampleItem
LAMBDA_HANDLER=tracker-handler
LAMBDA_GATEWAY=tracker-gateway
BUCKET_NAME=`jq -r '.appBucket' app.config`

ITEM_TO_TRACK_NAME=exampleItem

# Remove all items in the bucket
echo "Bucket to remove: ${BUCKET_NAME}"
aws s3 rm "s3://${BUCKET_NAME}" --recursive

# Delete dynamodb table
# Name of table come from returned name value from tracker event
echo "table to remove: ${ITEM_TO_TRACK_NAME}"
aws dynamodb delete-table \
    --table-name ${ITEM_TO_TRACK_NAME}

BUCKET_NAME=`jq -r '.appBucket' app.config`
echo "Bucket name: ${BUCKET_NAME}"
# Delete existing plots html in s3
aws s3 rm "s3://${BUCKET_NAME}" --recursive

# Delete the bucket
aws s3api delete-bucket \
    --bucket ${BUCKET_NAME}

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
echo "Gateway id: ${GATEWAY_ID}"

aws apigatewayv2 delete-api \
    --api-id ${GATEWAY_ID}

# Detach the policy from the role
aws iam detach-role-policy \
    --role-name tracker-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/tracker-policy"

aws iam detach-role-policy \
    --role-name handler-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/handler-policy"

aws iam detach-role-policy \
    --role-name gateway-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/gateway-policy"

# Delete the role
aws iam delete-role \
    --role-name tracker-role

aws iam delete-role \
    --role-name handler-role

aws iam delete-role \
    --role-name gateway-role

# Delete the policy
aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/tracker-policy"

aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/handler-policy"

aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/gateway-policy"
