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

# Transform agent_registry.yaml cloud_run URLs: 'https://host' → 'https://host/mcp'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-/workspace/config}"

IN="${CONFIG_DIR}/agent_registry.yaml"
OUT="${CONFIG_DIR}/agent_registry.yaml"

if [[ ! -f ${IN} ]]; then
	echo "ERROR: Registry not found: ${IN}" >&2
	exit 1
fi

yq eval '
  .mcp_servers |= map(
    select(.mode == "cloud_run") |
    .url = (.url | sub("/$"; "") | . + "/mcp")
  )
' "${IN}" >"${OUT}.tmp"

mv "${OUT}.tmp" "${OUT}"

echo "Updated cloud_run URLs in ${OUT}" >&2
