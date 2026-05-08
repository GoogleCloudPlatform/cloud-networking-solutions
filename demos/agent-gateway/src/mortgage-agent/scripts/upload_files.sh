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

# Entrypoint for Cloud Run mortgage-agent startup:
# 1. Render agent_config.yaml from registry mcp_tool_prefix entries
# 2. Strip policy_bindings from registry (Cloud Run has no IAM grants)
# 3. Append /mcp to cloud_run URLs in registry
# 4. Merge agent_config.yaml + agent_config_local.yaml → agent_config_merged.yaml
# 5. Upload merged config + registry to GCS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-/workspace/config}"
GCS_BUCKET="${GCS_BUCKET:-}"

show_help() {
	cat <<'EOF'
Usage: upload_files.sh [OPTIONS]

Cloud Run mortgage-agent startup script: renders config from registry,
cleans IAM bindings, updates URLs, merges configs, uploads to GCS.

OPTIONS:
  -h, --help              Show this help message
  -b, --bucket BUCKET     GCS bucket (gs://...) for upload (required)
  -c, --config-dir DIR    Config directory (default: /workspace/config)

ENVIRONMENT:
  GCS_BUCKET              GCS bucket for upload (alternative to --bucket)
  CONFIG_DIR              Config directory (alternative to --config-dir)

EXAMPLE:
  upload_files.sh --bucket gs://my-agent-config

EXIT CODES:
  0   Success
  1   Missing required parameter or file not found
  2   Script execution failure
EOF
}

main() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help
			exit 0
			;;
		-b | --bucket)
			GCS_BUCKET="$2"
			shift 2
			;;
		-c | --config-dir)
			CONFIG_DIR="$2"
			shift 2
			;;
		*)
			echo "ERROR: Unknown option: $1" >&2
			show_help >&2
			exit 1
			;;
		esac
	done

	if [[ -z ${GCS_BUCKET} ]]; then
		echo "ERROR: GCS_BUCKET not set (use --bucket or env var)" >&2
		exit 1
	fi

	echo "Starting mortgage-agent config pipeline..." >&2

	# Step 1: Render agent_config.yaml from registry
	echo "1/5 Rendering agent_config.yaml from registry..." >&2
	"${SCRIPT_DIR}/render-registry.py"

	# Step 2: Clear policy_bindings
	echo "2/5 Clearing policy_bindings from registry..." >&2
	"${SCRIPT_DIR}/clear-registry-bindings.sh"

	# Step 3: Update cloud_run URLs
	echo "3/5 Updating cloud_run URLs..." >&2
	"${SCRIPT_DIR}/update-registry-urls.sh"

	# Step 4: Merge configs
	echo "4/5 Merging agent_config.yaml + agent_config_local.yaml..." >&2
	"${SCRIPT_DIR}/merge-configs.sh"

	# Step 5: Upload to GCS
	echo "5/5 Uploading to ${GCS_BUCKET}..." >&2
	gsutil cp "${CONFIG_DIR}/agent_config_merged.yaml" "${GCS_BUCKET}/agent_config.yaml"
	gsutil cp "${CONFIG_DIR}/agent_registry.yaml" "${GCS_BUCKET}/agent_registry.yaml"

	echo "Config pipeline complete. Files uploaded to ${GCS_BUCKET}" >&2
}

main "$@"
