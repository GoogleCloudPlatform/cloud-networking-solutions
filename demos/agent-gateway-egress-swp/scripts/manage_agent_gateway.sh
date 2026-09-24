#!/bin/bash
# ==============================================================================
# Script: manage_agent_gateway.sh
# Purpose: Manages Agent Gateway lifecycle via the Network Services v1 REST API.
#          Avoids gcloud alpha (v1alpha1) bugs and supports agentConnectivityTemplate.
# Usage:
#   ./scripts/manage_agent_gateway.sh create <PROJECT_ID> <LOCATION> <GATEWAY_NAME> <TEMPLATE_NAME> <REGISTRY_URI>
#   ./scripts/manage_agent_gateway.sh delete <PROJECT_ID> <LOCATION> <GATEWAY_NAME>
# ==============================================================================
set -e

ACTION=$1

if [ "$ACTION" = "create" ]; then
  PROJECT_ID=$2
  LOCATION=$3
  GATEWAY_NAME=$4
  TEMPLATE_NAME=$5
  REGISTRY_URI=$6

  TOKEN=$(gcloud auth print-access-token)
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

  echo "Creating Agent Gateway ${GATEWAY_NAME} in ${LOCATION} linked to ${TEMPLATE_NAME} via v1 REST API..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "https://networkservices.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways?agentGatewayId=${GATEWAY_NAME}" \
    -d "{
      \"name\": \"projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways/${GATEWAY_NAME}\",
      \"protocols\": [\"MCP\"],
      \"googleManaged\": {
        \"governedAccessPath\": \"AGENT_TO_ANYWHERE\"
      },
      \"agentConnectivityTemplate\": \"projects/${PROJECT_NUMBER}/locations/${LOCATION}/agentConnectivityTemplates/${TEMPLATE_NAME}\",
      \"registries\": [\"${REGISTRY_URI}\"]
    }")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: Failed to initiate Agent Gateway creation (HTTP $HTTP_CODE):" >&2
    echo "$BODY" >&2
    exit 1
  fi

  OP_NAME=$(echo "$BODY" | jq -r .name 2>/dev/null || true)
  echo "Creation operation started: $OP_NAME"
  echo "Waiting for Agent Gateway creation to complete..."

  for i in $(seq 1 120); do
    OP_STATUS=$(curl -s -H "Authorization: Bearer ${TOKEN}" "https://networkservices.googleapis.com/v1/${OP_NAME}")
    DONE=$(echo "$OP_STATUS" | jq -r .done 2>/dev/null || true)
    if [ "$DONE" = "true" ]; then
      ERROR=$(echo "$OP_STATUS" | jq -r .error.message 2>/dev/null || true)
      if [ -n "$ERROR" ] && [ "$ERROR" != "null" ]; then
        echo "ERROR: Agent Gateway creation operation failed: $ERROR" >&2
        exit 1
      fi
      echo "Agent Gateway ${GATEWAY_NAME} created successfully."
      exit 0
    fi
    sleep 5
  done

  echo "ERROR: Timed out waiting for Agent Gateway creation." >&2
  exit 1

elif [ "$ACTION" = "delete" ]; then
  PROJECT_ID=$2
  LOCATION=$3
  GATEWAY_NAME=$4

  TOKEN=$(gcloud auth print-access-token)

  echo "Deleting Agent Gateway ${GATEWAY_NAME} in ${LOCATION} via v1 REST API..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://networkservices.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways/${GATEWAY_NAME}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [ "$HTTP_CODE" = "404" ]; then
    echo "Agent Gateway ${GATEWAY_NAME} does not exist. Skipping."
    exit 0
  elif [ "$HTTP_CODE" != "200" ]; then
    echo "Warning: Delete returned HTTP $HTTP_CODE: $BODY"
    exit 0
  fi

  OP_NAME=$(echo "$BODY" | jq -r .name 2>/dev/null || true)
  if [ -n "$OP_NAME" ] && [ "$OP_NAME" != "null" ]; then
    echo "Waiting for Agent Gateway deletion to complete..."
    for i in $(seq 1 60); do
      OP_STATUS=$(curl -s -H "Authorization: Bearer ${TOKEN}" "https://networkservices.googleapis.com/v1/${OP_NAME}")
      DONE=$(echo "$OP_STATUS" | jq -r .done 2>/dev/null || true)
      if [ "$DONE" = "true" ]; then
        echo "Agent Gateway deleted successfully."
        exit 0
      fi
      sleep 5
    done
  fi
  exit 0

else
  echo "Usage: $0 {create|delete} [args...]" >&2
  exit 1
fi
