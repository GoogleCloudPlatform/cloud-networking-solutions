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

# Foundation Module Outputs

output "foundation_project_id" {
  description = "The GCP project ID from the foundation module"
  value       = module.foundation.project_id
}

output "foundation_project_number" {
  description = "The GCP project number from the foundation module"
  value       = module.foundation.project_number
}

# Networking Module Outputs

output "vpc_id" {
  description = "The ID of the VPC network"
  value       = module.networking.network_id
}

output "vpc_name" {
  description = "The name of the VPC network"
  value       = module.networking.network_name
}

output "subnet_id" {
  description = "The ID of the primary subnet"
  value       = module.networking.subnet_id
}

output "subnet_name" {
  description = "Name of the primary subnet"
  value       = module.networking.subnet_name
}

output "subnet_self_link" {
  description = "The self-link of the primary subnet"
  value       = module.networking.subnet_self_link
}

output "network_self_link" {
  description = "The self-link of the VPC network"
  value       = module.networking.network_self_link
}

output "gateway_scope" {
  description = "The configured gateway scope (regional or null)"
  value       = var.gateway_scope
}

output "psc_subnet_id" {
  description = "The ID of the Private Service Connect subnet"
  value       = module.networking.psc_subnet_id
}

output "psc_subnet_self_link" {
  description = "The self-link of the Private Service Connect subnet"
  value       = module.networking.psc_subnet_self_link
}

# MCP Services (Cloud Run) Outputs

output "mcp_service_names" {
  description = "Map of MCP service key to Cloud Run service name"
  value       = module.mcp_services.service_names
}

output "mcp_service_urls" {
  description = "Map of MCP service key to Cloud Run *.run.app URL (only reachable via the internal LB)"
  value       = module.mcp_services.service_urls
}

output "mcp_service_account_emails" {
  description = "Map of MCP service key to runtime service account email"
  value       = module.mcp_services.service_account_emails
}

output "agent_mcp_invoker_email" {
  description = "Email of the SA agents impersonate when invoking MCP Cloud Run services. Pass to deploy_agent.py via --mcp-invoker-sa or $MCP_INVOKER_SA_EMAIL. Null when enable_agent_engine is false."
  value       = var.enable_agent_engine ? module.agent_engine[0].agent_mcp_invoker_email : null
}

# Artifact Registry Outputs

output "artifact_registry_id" {
  description = "The Artifact Registry repository ID"
  value       = google_artifact_registry_repository.registry.id
}

output "artifact_registry_url" {
  description = "The Artifact Registry repository URL for docker push/pull"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.registry.repository_id}"
}

# Model Armor Outputs

output "model_armor_request_template_id" {
  description = "Request-side Model Armor template ID"
  value       = var.enable_model_armor ? module.model_armor[0].request_template_id : null
}

output "model_armor_request_template_name" {
  description = "Request-side Model Armor template full resource name"
  value       = var.enable_model_armor ? module.model_armor[0].request_template_name : null
}

output "model_armor_response_template_id" {
  description = "Response-side Model Armor template ID"
  value       = var.enable_model_armor ? module.model_armor[0].response_template_id : null
}

output "model_armor_response_template_name" {
  description = "Response-side Model Armor template full resource name"
  value       = var.enable_model_armor ? module.model_armor[0].response_template_name : null
}

output "model_armor_inspect_template_id" {
  description = "DLP inspect template ID referenced by the response template's advanced SDP config (null when model_armor_sdp_enforcement = DISABLED)"
  value       = var.enable_model_armor ? module.model_armor[0].inspect_template_id : null
}

output "model_armor_deidentify_template_id" {
  description = "DLP de-identify template ID referenced by the response template's advanced SDP config (null when model_armor_sdp_enforcement = DISABLED)"
  value       = var.enable_model_armor ? module.model_armor[0].deidentify_template_id : null
}

output "model_armor_service_account" {
  description = "Service Extensions service account (gcp-sa-dep) used by the Agent Gateway to call Model Armor"
  value       = var.enable_model_armor ? module.model_armor[0].service_account_email : null
}

output "model_armor_service_agent_email" {
  description = "Model Armor service agent (gcp-sa-modelarmor) granted DLP read access (null when model_armor_sdp_enforcement = DISABLED)"
  value       = var.enable_model_armor ? module.model_armor[0].model_armor_service_agent_email : null
}

output "model_armor_gemini_enterprise_template_name" {
  description = "Full resource name of the Gemini Enterprise Model Armor template (for Discovery Engine REST API)"
  value       = var.enable_model_armor && var.enable_model_armor_gemini_enterprise ? module.model_armor[0].gemini_enterprise_template_name : null
}

output "model_armor_vertex_ai_service_account" {
  description = "AI Platform service agent email granted Model Armor access"
  value       = var.enable_model_armor && var.enable_model_armor_vertex_ai ? module.model_armor[0].vertex_ai_service_account_email : null
}

# PSC Interface Outputs

output "psc_interface_network_attachment_id" {
  description = "Network attachment ID for PSC Interface (pass to deploy_agent.py --network-attachment)"
  value       = var.enable_psc_interface ? module.networking.psc_interface_network_attachment_id : null
}

output "psc_interface_network_attachment_name" {
  description = "Network attachment name for PSC Interface"
  value       = var.enable_psc_interface ? module.networking.psc_interface_network_attachment_name : null
}

# Agent Gateway Outputs

output "agent_gateway_id" {
  description = "Full resource ID of the Agent Gateway"
  value       = var.enable_agent_gateway ? module.networking.agent_gateway_id : null
}

output "agent_gateway_registry_uri" {
  description = "URI of the project-local agent registry the gateway is bound to"
  value       = var.enable_agent_gateway ? module.networking.registry_uri : null
}

output "agent_gateway_subnet_self_link" {
  description = "Self link of the Agent Gateway dedicated co-location subnet"
  value       = var.enable_agent_gateway ? module.networking.agent_gateway_subnet_self_link : null
}

# Agent Registry Endpoints Outputs

output "agent_registry_service_ids" {
  description = "Map of registered Agent Registry service resource IDs, keyed by service_id"
  value       = var.enable_agent_registry_endpoints ? module.agent_registry_endpoints[0].service_ids : null
}
