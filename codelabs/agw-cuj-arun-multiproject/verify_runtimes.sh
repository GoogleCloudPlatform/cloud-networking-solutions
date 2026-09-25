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

REGION="${REGION:-us-central1}"
TOKEN=$(gcloud auth application-default print-access-token)

echo "=== 1. Purchasing Concierge ($PROJECT_CONCIERGE) ==="
curl -s -X GET "https://${REGION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_CONCIERGE}/locations/${REGION}/reasoningEngines/${CONCIERGE_ENGINE_ID}" \
	-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" |
	jq '{displayName: .displayName, identityType: .spec.identityType, effectiveIdentity: .spec.effectiveIdentity, agentGatewayConfig: .spec.deploymentSpec.agentGatewayConfig}'

echo "=== 2. Burger Agent ($PROJECT_SELLERS) ==="
curl -s -X GET "https://${REGION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_SELLERS}/locations/${REGION}/reasoningEngines/${BURGER_ENGINE_ID}" \
	-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" |
	jq '{displayName: .displayName, identityType: .spec.identityType, effectiveIdentity: .spec.effectiveIdentity, agentGatewayConfig: .spec.deploymentSpec.agentGatewayConfig}'

echo "=== 3. Pizza Agent ($PROJECT_SELLERS) ==="
curl -s -X GET "https://${REGION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_SELLERS}/locations/${REGION}/reasoningEngines/${PIZZA_ENGINE_ID}" \
	-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" |
	jq '{displayName: .displayName, identityType: .spec.identityType, effectiveIdentity: .spec.effectiveIdentity, agentGatewayConfig: .spec.deploymentSpec.agentGatewayConfig}'
