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

output "agent_gateway_id" {
  description = "Full resource ID of the Agent Gateway (pass to the agent-engine module as agent_gateway_id)"
  value       = "projects/${var.project_id}/locations/${var.region}/agentGateways/${var.name}"
}

output "agent_gateway_name" {
  description = "Short name of the Agent Gateway"
  value       = var.name
}

output "mtls_endpoint" {
  description = "mTLS endpoint clients use to reach the Agent Gateway"
  value       = null
}

output "root_certificates" {
  description = "Root certificates for validating the Agent Gateway mTLS endpoint."
  value       = null
  sensitive   = true
}

output "network_attachment_id" {
  description = "Full resource ID of the PSC-I network attachment created for the gateway"
  value       = google_compute_network_attachment.agent_gateway.id
}

output "registry_uri" {
  description = "URI of the project-local agent registry the gateway is bound to"
  value       = local.registry_uri
}

output "wait_for_gateway_id" {
  description = "ID of the time_sleep resource — pass as a dependency input to the agent-engine module so the engine is not created until the gateway is ready"
  value       = time_sleep.wait_for_gateway.id
}
