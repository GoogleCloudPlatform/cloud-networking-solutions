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

/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

# GKE Node Service Account Outputs

output "gke_node_service_account_email" {
  description = "Email address of the dedicated GKE node service account"
  value       = module.gke_node_service_account.email
}

output "gke_node_service_account_name" {
  description = "Resource name of the dedicated GKE node service account"
  value       = module.gke_node_service_account.name
}

output "gke_node_service_account_id" {
  description = "Account ID of the dedicated GKE node service account"
  value       = module.gke_node_service_account.id
}

# GKE Clusters Outputs

output "gke_cluster_names" {
  description = "Map of GKE cluster names by cluster key"
  value       = { for k, v in module.gke_clusters : k => v.name }
}

output "gke_cluster_ids" {
  description = "Map of GKE cluster IDs by cluster key"
  value       = { for k, v in module.gke_clusters : k => v.id }
}

output "gke_cluster_endpoints" {
  description = "Map of GKE cluster endpoints by cluster key"
  value       = { for k, v in module.gke_clusters : k => v.endpoint }
  sensitive   = true
}

output "gke_cluster_ca_certificates" {
  description = "Map of GKE cluster CA certificates by cluster key"
  value       = { for k, v in module.gke_clusters : k => v.ca_certificate }
  sensitive   = true
}

output "gke_workload_identity_pools" {
  description = "Map of Workload Identity pools by cluster key"
  value       = { for k, v in module.gke_clusters : k => v.workload_identity_pool }
}

# DNS Module Outputs

output "internal_gateway_fqdn" {
  description = "Internal FQDN for the main gateway"
  value       = var.dns_zone_domain != null ? module.dns[0].internal_gateway_fqdn : null
}

output "internal_gateway_ip_name" {
  description = "Name of the internal static IP for Gateway annotations (from networking module)"
  value       = module.networking.internal_gateway_ip_name
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

# Certificate Outputs

output "regional_certificate_name" {
  description = "Name of the regional Google-managed certificate"
  value       = var.enable_certificate_manager ? module.certificates[0].regional_certificate_name : null
}

# Model Armor Outputs

output "model_armor_template_id" {
  description = "Model Armor template ID"
  value       = var.enable_model_armor ? module.model_armor[0].template_id : null
}

output "model_armor_template_name" {
  description = "Model Armor template name"
  value       = var.enable_model_armor ? module.model_armor[0].template_name : null
}

output "model_armor_service_account" {
  description = "Model Armor service account email"
  value       = var.enable_model_armor ? module.model_armor[0].service_account_email : null
}

output "model_armor_gemini_enterprise_template_name" {
  description = "Full resource name of the Gemini Enterprise Model Armor template (for Discovery Engine REST API)"
  value       = var.enable_model_armor && var.enable_model_armor_gemini_enterprise ? module.model_armor[0].gemini_enterprise_template_name : null
}

output "model_armor_vertex_ai_service_account" {
  description = "AI Platform service agent email granted Model Armor access"
  value       = var.enable_model_armor && var.enable_model_armor_vertex_ai ? module.model_armor[0].vertex_ai_service_account_email : null
}

# DLP ext_proc Outputs

output "dlp_ext_proc_service_url" {
  description = "URL of the DLP ext_proc Cloud Run service"
  value       = var.enable_dlp_ext_proc ? module.dlp_ext_proc[0].cloud_run_service_url : null
}

output "dlp_ext_proc_service_account" {
  description = "Service account email for the DLP ext_proc service"
  value       = var.enable_dlp_ext_proc ? module.dlp_ext_proc[0].service_account_email : null
}

output "dlp_ext_proc_traffic_extension_id" {
  description = "ID of the DLP ext_proc LB traffic extension"
  value       = var.enable_dlp_ext_proc ? module.dlp_ext_proc[0].traffic_extension_id : null
}

# Apigee Outputs

output "apigee_org_id" {
  description = "Apigee organization ID"
  value       = var.enable_apigee ? module.apigee[0].org_id : null
}

output "apigee_org_name" {
  description = "Apigee organization name"
  value       = var.enable_apigee ? module.apigee[0].org_name : null
}

output "apigee_tenant_project_id" {
  description = "Apigee tenant project ID"
  value       = var.enable_apigee ? module.apigee[0].tenant_project_id : null
}

output "apigee_envgroups" {
  description = "Map of Apigee environment groups"
  value       = var.enable_apigee ? module.apigee[0].envgroups : {}
}

output "apigee_environments" {
  description = "Map of Apigee environments"
  value       = var.enable_apigee ? module.apigee[0].environments : {}
}

output "apigee_instances" {
  description = "Map of Apigee instances"
  value       = var.enable_apigee ? module.apigee[0].instances : {}
}

output "apigee_proxy_runtime_sa_email" {
  description = "Apigee proxy runtime service account email"
  value       = var.enable_apigee ? module.apigee[0].proxy_runtime_sa_email : null
}

output "apigee_apim_operator_sa_email" {
  description = "Apigee APIM Operator service account email"
  value       = var.enable_apigee ? module.apigee[0].apim_operator_sa_email : null
}

output "apigee_endpoint_attachment_hosts" {
  description = "Map of Apigee endpoint attachment hosts"
  value       = var.enable_apigee ? module.apigee[0].endpoint_attachment_hosts : {}
}

output "apigee_northbound_lb_ip" {
  description = "Apigee northbound load balancer internal IP"
  value       = var.enable_apigee && var.apigee_enable_northbound_lb ? module.apigee[0].northbound_lb_ip : null
}

output "apigee_dns_peering_zones" {
  description = "Apigee DNS peering zones"
  value       = var.enable_apigee ? module.apigee[0].dns_peering_zones : {}
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

output "psc_interface_dns_zone_name" {
  description = "DNS zone name for PSC Interface DNS peering"
  value       = var.enable_psc_interface ? module.networking.psc_interface_dns_zone_name : null
}

output "psc_interface_dns_domain" {
  description = "Domain name for PSC Interface DNS peering (ends with a dot)"
  value       = var.enable_psc_interface ? module.networking.psc_interface_dns_domain : null
}

output "psc_interface_dns_peering_domain" {
  description = "DNS domain for PSC Interface DNS peering (pass to deploy_agent.py --dns-peering-domain)"
  value       = var.enable_psc_interface && var.psc_interface_dns_zone != null ? var.psc_interface_dns_zone.domain : null
}
