#!/usr/bin/env bash

# Trigger Codemagic iOS Build & Publish Workflow

# Replace these placeholders with your actual Codemagic values, or set them as environment variables
CM_API_KEY="${CODEMAGIC_API_KEY:-YOUR_API_KEY}"
CM_APP_ID="${CODEMAGIC_APP_ID:-YOUR_APP_ID}"
WORKFLOW_ID="ios-build-and-publish"
BRANCH="main"

if [ "$CM_API_KEY" == "YOUR_API_KEY" ] || [ "$CM_APP_ID" == "YOUR_APP_ID" ]; then
    echo "Please set CODEMAGIC_API_KEY and CODEMAGIC_APP_ID environment variables or update the placeholders in this script."
    exit 1
fi

echo "Triggering Codemagic build for '$WORKFLOW_ID' on branch '$BRANCH'..."

curl -s -X POST "https://api.codemagic.io/builds" \
  -H "Content-Type: application/json" \
  -H "x-auth-token: $CM_API_KEY" \
  -d '{
    "appId": "'"$CM_APP_ID"'",
    "workflowId": "'"$WORKFLOW_ID"'",
    "branch": "'"$BRANCH"'"
  }'

echo ""
echo "Build triggered. Check your Codemagic dashboard for status."
