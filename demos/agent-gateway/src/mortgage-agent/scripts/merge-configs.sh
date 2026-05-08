#!/bin/bash
# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Merge agent_config.yaml + agent_config_local.yaml → agent_config_merged.yaml via yq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-/workspace/config}"

BASE="${CONFIG_DIR}/agent_config.yaml"
LOCAL="${CONFIG_DIR}/agent_config_local.yaml"
OUT="${CONFIG_DIR}/agent_config_merged.yaml"

if [[ ! -f "${BASE}" ]]; then
	echo "ERROR: Base config not found: ${BASE}" >&2
	exit 1
fi

if [[ ! -f "${LOCAL}" ]]; then
	echo "WARNING: Local config not found: ${LOCAL}, using base only" >&2
	cp "${BASE}" "${OUT}"
	exit 0
fi

yq eval-all '. as $item ireduce ({}; . *+ $item)' "${BASE}" "${LOCAL}" >"${OUT}"

echo "Merged ${BASE} + ${LOCAL} → ${OUT}" >&2
