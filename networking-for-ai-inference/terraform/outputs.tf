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

# Vertex AI and Semantic Cache Outputs

output "vertex_ai_index_id" {
  description = "ID of the Vertex AI vector search index"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_index_id : null
}

output "vertex_ai_index_name" {
  description = "Name of the Vertex AI vector search index"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_index_name : null
}

output "vertex_ai_deployed_index_id" {
  description = "ID of the deployed Vertex AI index"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_deployed_index_id : null
}

output "vertex_ai_index_endpoint_id" {
  description = "ID of the public Vertex AI index endpoint"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_endpoint_id : null
}

output "vertex_ai_index_endpoint_domain" {
  description = "Public domain name for the Vertex AI index endpoint"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_public_endpoint_domain : null
}

output "semantic_cache_bucket_name" {
  description = "Name of the GCS bucket for semantic cache storage"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_bucket_name : null
}

# Apigee Outputs

output "apigee_organization_id" {
  description = "Apigee organization ID"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].apigee_org_id : null
}

output "apigee_environments" {
  description = "Map of Apigee environment names to their IDs"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].apigee_environments : null
}

output "apigee_envgroups" {
  description = "Map of Apigee environment group names to their IDs"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].apigee_envgroups : null
}

output "apigee_instances" {
  description = "Map of Apigee instance regions to their details"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].apigee_instances : null
}

output "apigee_endpoint" {
  description = "Apigee runtime endpoint"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].apigee_endpoint : null
}

# Vertex AI Numeric IDs (needed by deploy.sh for proxy policy rendering)

output "vertex_ai_endpoint_numeric_id" {
  description = "Numeric ID of the Vertex AI index endpoint"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_endpoint_numeric_id : null
}

output "vertex_ai_index_numeric_id" {
  description = "Numeric ID of the Vertex AI index"
  value       = var.enable_semantic_cache ? module.semantic_cache[0].vertex_ai_index_numeric_id : null
}


# Storage Module Outputs

output "gcs_bucket_name" {
  description = "Name of the GCS bucket for model storage"
  value       = module.storage.bucket_name
}

output "model_storage_bucket_url" {
  description = "URL of the GCS bucket for model storage"
  value       = module.storage.bucket_url
}

output "artifact_registry_url" {
  description = "URL for the Docker artifact registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_name}"
}

output "artifact_registry_id" {
  description = "ID of the Artifact Registry repository"
  value       = module.artifact_registry.id
}

output "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  value       = module.artifact_registry.name
}

output "huggingface_secret_id" {
  description = "Secret Manager ID for HuggingFace token (if created)"
  value       = var.huggingface_token != null ? google_secret_manager_secret.huggingface_token[0].secret_id : null
  sensitive   = true
}

output "huggingface_secret_name" {
  description = "Full resource name of HuggingFace secret (null if not created)"
  value       = var.huggingface_token != null ? google_secret_manager_secret.huggingface_token[0].name : null
  sensitive   = true
}

output "huggingface_secret_version" {
  description = "Current version of HuggingFace secret (null if not created)"
  value       = var.huggingface_token != null ? google_secret_manager_secret_version.huggingface_token[0].name : null
  sensitive   = true
}

# Certificate Module Outputs

output "certificate_map_id" {
  description = "Certificate Manager map ID (regional)"
  value       = var.enable_certificate_manager ? module.certificates[0].regional_certificate_id : null
}

output "certificate_ids" {
  description = "Certificate Manager certificate IDs"
  value       = var.enable_certificate_manager ? module.certificates[0].certificate_ids : null
}

# DNS Module Outputs

output "internal_gateway_fqdn" {
  description = "Internal FQDN for the main gateway"
  value       = var.dns_zone_domain != null ? module.dns[0].internal_gateway_fqdn : null
}


# Model Armor Module Outputs

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

# ==============================================================================
# SELF MANAGED INFERENCE GATEWAY OUTPUTS (PHASE 11)
# ==============================================================================

output "self_managed_gateway_ip" {
  description = "External IP address of the self managed inference gateway"
  value       = var.self_managed_gateway != null ? module.self_managed_inference_gateway[0].effective_gateway_ip : null
}

output "self_managed_gateway_url" {
  description = "URL of the self managed inference gateway"
  value       = var.self_managed_gateway != null ? module.self_managed_inference_gateway[0].gateway_url : null
}

output "self_managed_gateway_domain" {
  description = "Domain name of the self managed inference gateway"
  value       = var.self_managed_gateway != null ? var.self_managed_gateway.domain.name : null
}

output "self_managed_gateway_ssl_certificate_id" {
  description = "ID of the self managed gateway SSL certificate"
  value       = var.self_managed_gateway != null ? module.self_managed_inference_gateway[0].ssl_certificate_id : null
}

output "self_managed_gateway_enabled_backends" {
  description = "List of enabled backend types for self managed gateway"
  value       = var.self_managed_gateway != null ? module.self_managed_inference_gateway[0].enabled_backends : []
}

# ==============================================================================
# GKE INFERENCE GATEWAY OUTPUTS
# ==============================================================================

output "gke_gateway_hostname" {
  description = "Hostname for the GKE inference gateway"
  value       = var.gke_gateway != null ? var.gke_gateway.gateway.hostname : null
}

output "internal_gateway_ip_name" {
  description = "Name of the internal static IP for Gateway annotations (from networking module)"
  value       = module.networking.internal_gateway_ip_name
}
