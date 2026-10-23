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

# -----------------------------------------------------------------------------
# Projects
# -----------------------------------------------------------------------------

output "governance_project_id" {
  description = "GCP Governance (Service) project ID"
  value       = module.foundation.governance_project_id
}

output "governance_project_number" {
  description = "GCP Governance (Service) project number"
  value       = module.foundation.governance_project_number
}

output "networking_project_id" {
  description = "GCP Networking (Host) project ID"
  value       = module.foundation.networking_project_id
}

output "networking_project_number" {
  description = "GCP Networking (Host) project number"
  value       = module.foundation.networking_project_number
}

output "runtime_project_id" {
  description = "GCP Runtime (Service) project ID"
  value       = module.foundation.runtime_project_id
}

output "runtime_project_number" {
  description = "GCP Runtime (Service) project number"
  value       = module.foundation.runtime_project_number
}

# -----------------------------------------------------------------------------
# Shared VPC & Networking
# -----------------------------------------------------------------------------

output "vpc_name" {
  description = "Shared VPC network name"
  value       = module.networking.network_name
}

output "network_self_link" {
  description = "Shared VPC network self-link"
  value       = module.networking.network_self_link
}

output "nat_static_ip" {
  description = "Reserved static external IP used by Cloud NAT in the Networking project."
  value       = module.networking.nat_static_ip
}

output "agent_gateway_subnet_self_link" {
  description = "Self-link of the Agent Gateway PSC-I dedicated subnet in the Shared VPC"
  value       = module.networking.agent_gateway_subnet_self_link
}

# -----------------------------------------------------------------------------
# Secure Web Proxy (Networking Project)
# -----------------------------------------------------------------------------

output "swp_gateway_id" {
  description = "Resource ID of the Secure Web Proxy gateway in the Networking project"
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

# -----------------------------------------------------------------------------
# MCP Cloud Run services (Governance Project)
# -----------------------------------------------------------------------------

output "mcp_service_urls" {
  description = "Map of MCP service name to public Cloud Run URL (*.run.app)."
  value       = module.mcp_services.service_urls
}

output "bug_tickets_mcp_url" {
  description = "Public URL of the bug-tickets-mcp Cloud Run service."
  value       = try("${module.mcp_services.service_urls["bug-tickets-mcp"]}/mcp", null)
}

# -----------------------------------------------------------------------------
# Artifact Registry (Governance Project)
# -----------------------------------------------------------------------------

output "artifact_registry_url" {
  description = "Artifact Registry URL for docker push/pull in the Governance project"
  value       = "${var.region}-docker.pkg.dev/${var.governance_project_id}/${google_artifact_registry_repository.registry.repository_id}"
}

# -----------------------------------------------------------------------------
# Agent Gateway (Governance Project, PSC-I to Shared VPC)
# -----------------------------------------------------------------------------

output "agent_gateway_id" {
  description = "Full resource ID of the Agent Gateway (used by the Reasoning Engine agent_gateway_config)"
  value       = module.agent_gateway.agent_gateway_id
}

output "agent_gateway_name" {
  description = "Short name of the Agent Gateway"
  value       = module.agent_gateway.agent_gateway_name
}

output "network_attachment_id" {
  description = "Resource ID of the PSC-I Network Attachment in the Governance project"
  value       = module.agent_gateway.network_attachment_id
}

output "agent_connectivity_template_id" {
  description = "Resource ID of the Agent Connectivity Template"
  value       = module.agent_gateway.template_id
}

output "agent_connectivity_template_name" {
  description = "Short name of the Agent Connectivity Template"
  value       = module.agent_gateway.template_name
}

# -----------------------------------------------------------------------------
# Model Armor (Governance Project)
# -----------------------------------------------------------------------------

output "model_armor_request_template_id" {
  description = "Model Armor request template ID"
  value       = var.enable_model_armor ? module.model_armor.request_template_id : null
}

output "model_armor_request_template_name" {
  description = "Model Armor request template full resource name"
  value       = var.enable_model_armor ? module.model_armor.request_template_name : null
}

output "model_armor_response_template_id" {
  description = "Model Armor response template ID"
  value       = var.enable_model_armor ? module.model_armor.response_template_id : null
}

output "model_armor_response_template_name" {
  description = "Model Armor response template full resource name"
  value       = var.enable_model_armor ? module.model_armor.response_template_name : null
}

# -----------------------------------------------------------------------------
# Agent Engine (Governance Project)
# -----------------------------------------------------------------------------

output "agent_identity_principal" {
  description = "Principal set identifier used for Agent Identity IAM bindings"
  value       = module.agent_engine.agent_identity_principal
}

output "reasoning_engine_name" {
  description = "Resource name of the deployed Vertex AI Reasoning Engine (null if deploy_reasoning_engine = false)"
  value       = module.agent_engine.reasoning_engine_name
}
