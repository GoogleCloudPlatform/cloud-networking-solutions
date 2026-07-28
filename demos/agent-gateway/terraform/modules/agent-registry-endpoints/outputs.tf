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

output "service_ids" {
  description = "Map of registered Agent Registry service resource IDs, keyed by service_id."
  value = merge(
    { (google_agent_registry_service.google_apis.service_id) = google_agent_registry_service.google_apis.id },
    { for k, r in google_agent_registry_service.custom : k => r.id },
    { for k, r in google_agent_registry_service.mcp : k => r.id },
  )
}

# Ordering handle. The agent's egress to a registered endpoint (googleapis and
# the custom services) is only permitted once the roles/iap.egressor binding
# exists, but nothing in the graph relates those bindings to the reasoning
# engine: iap_egressor_members is the project-wide principalSet, a pure string
# built from organization_id/project_number, so the two sit in unrelated
# branches and Terraform may create the engine first. Feed this into the
# agent-engine module's engine_depends_on to pin the order.
#
# Deliberately scoped to the endpoint bindings. The MCP-server bindings key on
# the *per-agent* identity, which cannot exist until the engine does, so they
# must stay downstream — including them here would be a cycle.
output "endpoint_egressor_binding_ids" {
  description = "IDs of the roles/iap.egressor bindings on the NO_SPEC endpoints (googleapis + custom). Pass to agent-engine's engine_depends_on so the engine is not created before the agent may egress."
  value       = [for b in google_iap_agent_registry_endpoint_iam_member.endpoint_egressor : b.id]
}
