#!/bin/bash

# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Validation
if [ -z "$PROJECT_ID" ] || [ -z "$LOCATION" ]; then
  echo "Error: PROJECT_ID and LOCATION environment variables must be set."
  exit 1
fi

echo "Deploying Agent Registry Services for: $PROJECT_ID in $LOCATION"

# Helper function for no-spec registration (Google APIs and custom services)
reg_svc() {
  local svc_id=$1
  local display_name=$2
  local url=$3
  local desc=$4

  # Check if service already exists
  if gcloud alpha agent-registry services describe "$svc_id" --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; then
    echo "Service $svc_id already exists, skipping creation."
    return 0
  fi

  echo "Registering: $svc_id ($display_name) at $url"

  gcloud alpha agent-registry services create "$svc_id" \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    --display-name="$display_name" \
    --endpoint-spec-type=no-spec \
    $${desc:+--description="$desc"} \
    --interfaces="url=$url,protocolBinding=JSONRPC"
}

# Helper function for MCP server registration with a tool spec
reg_mcp_svc() {
  local svc_id=$1
  local display_name=$2
  local url=$3
  local desc=$4
  local tool_spec_path=$5

  if gcloud alpha agent-registry services describe "$svc_id" --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; then
    echo "MCP service $svc_id already exists, skipping creation."
    return 0
  fi

  if [[ ! -f "$tool_spec_path" ]]; then
    echo "ERROR: tool spec file not found for $svc_id: $tool_spec_path"
    return 1
  fi

  echo "Registering MCP server: $svc_id ($display_name) at $url with spec $tool_spec_path"

  gcloud alpha agent-registry services create "$svc_id" \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    --display-name="$display_name" \
    --mcp-server-spec-type=tool-spec \
    --mcp-server-spec-content="$tool_spec_path" \
    $${desc:+--description="$desc"} \
    --interfaces="url=$url,protocolBinding=JSONRPC"
}

### 1. Google APIs with multiple variants
%{ for id, name in google_apis ~}
# Variants for ${name} (${id})
reg_svc "${id}" "${name}" "https://${id}.googleapis.com"
reg_svc "${id}-mtls" "${name} mTLS" "https://${id}.mtls.googleapis.com"
reg_svc "$${LOCATION}-${id}" "${name} Locational" "https://$${LOCATION}-${id}.googleapis.com"
reg_svc "$${LOCATION}-${id}-mtls" "${name} Locational mTLS" "https://$${LOCATION}-${id}.mtls.googleapis.com"
reg_svc "${id}-$${LOCATION}-rep" "${name} Regional (REP)" "https://${id}.$${LOCATION}.rep.googleapis.com"
%{ endfor ~}

### 2. Custom Services
%{ for svc in custom_services ~}
reg_svc "${svc.id}" "${svc.display_name}" "${svc.url}" "${svc.description != null ? svc.description : ""}"
%{ endfor ~}

### 3. MCP Servers (Cloud Run)
%{ for name, svc in mcp_servers ~}
reg_mcp_svc "${svc.id}" "${svc.display_name}" "${svc.url}" "${svc.description != null ? svc.description : ""}" "${svc.tool_spec_path}"
%{ endfor ~}

echo "Full deployment for region $LOCATION complete."
