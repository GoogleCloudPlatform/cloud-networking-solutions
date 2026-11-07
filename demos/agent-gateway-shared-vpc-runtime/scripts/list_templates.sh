#!/bin/bash
# ==============================================================================
# Script: list_templates.sh
# Purpose: Lists all AgentConnectivityTemplate resources in a given region via
#          the Network Services v1 REST API.
# Usage: ./scripts/list_templates.sh <PROJECT_ID> <LOCATION>
# Role: Inspection and troubleshooting utility.
# ==============================================================================
set -e

PROJECT=$1
LOCATION=$2

if [ -z "$PROJECT" ] || [ -z "$LOCATION" ]; then
  echo "Usage: ./scripts/list_templates.sh <PROJECT_ID> <LOCATION>"
  exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format="value(projectNumber)")
TOKEN=$(gcloud auth print-access-token)

curl -s -H "Authorization: Bearer $TOKEN" "https://networkservices.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/agentConnectivityTemplates" | jq .
