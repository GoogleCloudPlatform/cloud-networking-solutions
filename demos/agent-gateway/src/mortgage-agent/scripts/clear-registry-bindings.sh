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

# Clear IAM policy_bindings from agent_registry.yaml MCP server entries

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-/workspace/config}"

REGISTRY="${CONFIG_DIR}/agent_registry.yaml"

if [[ ! -f ${REGISTRY} ]]; then
	echo "ERROR: Registry not found: ${REGISTRY}" >&2
	exit 1
fi

yq eval 'del(.mcp_servers[].policy_bindings)' "${REGISTRY}" >"${REGISTRY}.tmp"

mv "${REGISTRY}.tmp" "${REGISTRY}"

echo "Cleared policy_bindings from ${REGISTRY}" >&2
