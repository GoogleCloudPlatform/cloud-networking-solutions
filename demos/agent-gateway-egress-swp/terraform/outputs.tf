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



# Foundation

output "project_id" {
  description = "GCP project ID"
  value       = module.foundation.project_id
}

output "project_number" {
  description = "GCP project number"
  value       = module.foundation.project_number
}

# Networking

output "vpc_name" {
  description = "VPC network name"
  value       = module.networking.network_name
}

output "network_self_link" {
  description = "VPC network self-link"
  value       = module.networking.network_self_link
}

output "nat_static_ip" {
  description = "Reserved static external IP used by Cloud NAT. This is the address the MCP Cloud Run service (and any other public endpoint the agent reaches) will see as the egress source IP. Verify it in Cloud Run request logs under the X-Forwarded-For header."
  value       = module.networking.nat_static_ip
}

output "agent_gateway_subnet_self_link" {
  description = "Self-link of the Agent Gateway PSC-I dedicated subnet"
  value       = module.networking.agent_gateway_subnet_self_link
}

# Secure Web Proxy

output "swp_gateway_id" {
  description = "Resource ID of the Secure Web Proxy gateway"
  value       = module.secure_web_proxy.gateway_id
}

output "swp_gateway_internal_ip" {
  description = "Internal IP of the SWP gateway (next-hop IP in the policy-based route)"
  value       = module.secure_web_proxy.gateway_internal_ip
}

output "swp_proxy_subnet_cidr" {
  description = "CIDR of the SWP proxy-only subnet"
  value       = module.secure_web_proxy.proxy_subnet_cidr
}

# MCP Cloud Run services

output "mcp_service_urls" {
  description = "Map of MCP service name to public Cloud Run URL (*.run.app). Append /mcp to form the MCPToolset endpoint."
  value       = module.mcp_services.service_urls
}

output "bug_tickets_mcp_url" {
  description = "Public URL of the bug-tickets-mcp Cloud Run service. The agent connects its MCPToolset to <this_url>/mcp."
  value       = try("${module.mcp_services.service_urls["bug-tickets-mcp"]}/mcp", null)
}

# Artifact Registry

output "artifact_registry_url" {
  description = "Artifact Registry URL for docker push/pull"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.registry.repository_id}"
}

# Agent Gateway

output "agent_gateway_id" {
  description = "Full resource ID of the Agent Gateway (used by the Reasoning Engine agent_gateway_config)"
  value       = module.agent_gateway.agent_gateway_id
}

output "agent_gateway_mtls_endpoint" {
  description = "mTLS endpoint for the Agent Gateway"
  value       = module.agent_gateway.mtls_endpoint
}

output "agent_gateway_root_certificates" {
  description = "Root certificates for validating the Agent Gateway mTLS endpoint (sensitive)"
  value       = module.agent_gateway.root_certificates
  sensitive   = true
}

# Agent Engine

output "reasoning_engine_name" {
  description = "Full resource name of the deployed reasoning engine. Null unless deploy_reasoning_engine = true."
  value       = module.agent_engine.reasoning_engine_name
}

output "agent_identity_principal" {
  description = "Project-wide agent principal set for all Agent Engine agents in this project."
  value       = module.agent_engine.agent_identity_principal
}

output "network_attachment_id" {
  description = "The ID of the PSC-Interface network attachment, required for the AgentConnectivityTemplate."
  value       = module.agent_gateway.network_attachment_id
}

output "agent_gateway_name" {
  description = "The short name of the Agent Gateway."
  value       = module.agent_gateway.agent_gateway_name
}
