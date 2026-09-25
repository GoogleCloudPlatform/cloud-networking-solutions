#!/bin/bash
# ==============================================================================
# Script: delete_connectivity_template.sh
# Purpose: Deletes an AgentConnectivityTemplate resource via the Network Services
#          v1 REST API. Handles pre-GA reference retention gracefully.
# Usage: ./scripts/delete_connectivity_template.sh <PROJECT_ID> <LOCATION> <TEMPLATE_NAME>
# Called by: terraform/modules/agent-gateway/main.tf (terraform_data.agent_gateway local-exec destroy)
# ==============================================================================
set -e

PROJECT_ID=$1
LOCATION=$2
TEMPLATE_NAME=$3

if [ -z "$PROJECT_ID" ] || [ -z "$LOCATION" ] || [ -z "$TEMPLATE_NAME" ]; then
  echo "Usage: ./scripts/delete_connectivity_template.sh <PROJECT_ID> <LOCATION> <TEMPLATE_NAME>"
  exit 1
fi

TOKEN=$(gcloud auth print-access-token)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

echo "Deleting AgentConnectivityTemplate ${TEMPLATE_NAME} in ${LOCATION}..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://networkservices.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/agentConnectivityTemplates/${TEMPLATE_NAME}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "AgentConnectivityTemplate ${TEMPLATE_NAME} deletion initiated successfully."
elif [ "$HTTP_CODE" = "404" ]; then
  echo "AgentConnectivityTemplate ${TEMPLATE_NAME} not found or already deleted."
elif [ "$HTTP_CODE" = "400" ]; then
  echo "Note: Template ${TEMPLATE_NAME} is retained by Google Cloud's pre-GA async reaper (status 400)."
  echo "It carries \$0.00 cost and will be seamlessly updated and reused on the next terraform apply."
else
  echo "Warning: Delete returned HTTP $HTTP_CODE: $BODY"
fi

echo "Done deleting."
