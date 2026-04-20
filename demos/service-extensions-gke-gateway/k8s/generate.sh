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

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z ${PROJECT_ID:-} ]]; then
	echo "Error: PROJECT_ID is not set" >&2
	exit 1
fi

if [[ -z ${BASE_DOMAIN:-} ]]; then
	echo "Error: BASE_DOMAIN is not set" >&2
	exit 1
fi

export PROJECT_ID BASE_DOMAIN

count=0
while IFS= read -r -d '' tmpl; do
	output="${tmpl%.tmpl}"
	envsubst '${PROJECT_ID} ${BASE_DOMAIN}' <"${tmpl}" >"${output}"
	echo "  Generated: ${output#"${SCRIPT_DIR}"/}"
	count=$((count + 1))
done < <(find "${SCRIPT_DIR}" -name '*.yaml.tmpl' -print0)

echo "Done. Generated ${count} files from templates."
