#!/bin/bash
# ==============================================================================
# Script: delete_connectivity_template.sh
# Purpose: Deletes an AgentConnectivityTemplate resource via the Network Services
#          v1 REST API.
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

curl -s -X DELETE \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://networkservices.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/agentConnectivityTemplates/${TEMPLATE_NAME}"

echo ""
echo "Done deleting."
