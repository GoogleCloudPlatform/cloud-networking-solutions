#!/bin/bash
# ==============================================================================
# Script: create_connectivity_template.sh
# Purpose: Provisions an AgentConnectivityTemplate resource via the Network Services
#          v1 REST API. This binds the Reasoning Engine container's egress to
#          the customer VPC PSC-I Network Attachment in ALL_TRAFFIC mode and sets
#          up Cloud DNS peering for googleapis.com.
# Usage: ./scripts/create_connectivity_template.sh <PROJECT_ID> <LOCATION> <TEMPLATE_NAME> <NETWORK_ATTACHMENT_URI> <TARGET_VPC_NETWORK_URI>
# Called by: terraform/modules/agent-gateway/main.tf (terraform_data.agent_gateway local-exec)
# ==============================================================================
set -e

PROJECT_ID=$1
LOCATION=$2
TEMPLATE_NAME=$3
NETWORK_ATTACHMENT_URI=$4
TARGET_VPC_NETWORK_URI=$5

if [ -z "$PROJECT_ID" ] || [ -z "$LOCATION" ] || [ -z "$TEMPLATE_NAME" ] || [ -z "$NETWORK_ATTACHMENT_URI" ] || [ -z "$TARGET_VPC_NETWORK_URI" ]; then
  echo "Usage: ./scripts/create_connectivity_template.sh <PROJECT_ID> <LOCATION> <TEMPLATE_NAME> <NETWORK_ATTACHMENT_URI> <TARGET_VPC_NETWORK_URI>"
  exit 1
fi

TOKEN=$(gcloud auth print-access-token)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

echo "Creating AgentConnectivityTemplate ${TEMPLATE_NAME} in ${LOCATION}..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://networkservices.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/agentConnectivityTemplates?agentConnectivityTemplateId=${TEMPLATE_NAME}" \
  -d "{
    \"accessPath\": \"AGENT_TO_ANYWHERE\",
    \"deploymentModel\": \"CENTRALIZED\",
    \"egressNetworkConfig\": {
      \"networkAttachment\": \"${NETWORK_ATTACHMENT_URI}\",
      \"vpcEgress\": \"ALL_TRAFFIC\",
      \"dnsPeeringConfig\": {
        \"domain\": \"googleapis.com.\",
        \"targetNetwork\": \"${TARGET_VPC_NETWORK_URI}\"
      }
    }
  }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "409" ]; then
  echo "Template ${TEMPLATE_NAME} already exists. Attempting PATCH to ensure network config is current..."
  curl -s -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "https://networkservices.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/agentConnectivityTemplates/${TEMPLATE_NAME}?updateMask=egressNetworkConfig" \
    -d "{
      \"egressNetworkConfig\": {
        \"networkAttachment\": \"${NETWORK_ATTACHMENT_URI}\",
        \"vpcEgress\": \"ALL_TRAFFIC\",
        \"dnsPeeringConfig\": {
          \"domain\": \"googleapis.com.\",
          \"targetNetwork\": \"${TARGET_VPC_NETWORK_URI}\"
        }
      }
    }" || true
else
  echo "$BODY"
fi

echo ""
echo "Note: The AgentGateway configuration in Terraform needs to reference this template's name."
