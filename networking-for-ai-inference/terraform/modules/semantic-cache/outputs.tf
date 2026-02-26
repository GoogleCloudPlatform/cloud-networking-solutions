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

# ==============================================================================
# APIGEE OUTPUTS (from primitive module)
# ==============================================================================

output "apigee_org_id" {
  description = "Apigee organization ID"
  value       = module.apigee.org_id
}

output "apigee_org_name" {
  description = "Apigee organization name"
  value       = module.apigee.org_name
}

output "apigee_tenant_project_id" {
  description = "Apigee tenant project ID (for PSC connections)"
  value       = module.apigee.tenant_project_id
}

output "apigee_envgroups" {
  description = "Map of Apigee environment group names to their details"
  value       = module.apigee.envgroups
}

output "apigee_environments" {
  description = "Map of Apigee environment names to their details"
  value       = module.apigee.environments
}

output "apigee_environment_ids" {
  description = "Map of environment names to their IDs"
  value       = module.apigee.environment_ids
}

output "apigee_instances" {
  description = "Map of Apigee instance regions to their details"
  value       = module.apigee.instances
}

output "apigee_endpoint" {
  description = "Apigee runtime endpoint"
  value       = module.apigee.endpoint
}

output "apigee_endpoint_attachment_hosts" {
  description = "Map of endpoint attachment names to their PSC endpoint hosts/IPs"
  value       = module.apigee.endpoint_attachment_hosts
}

# ==============================================================================
# VERTEX AI OUTPUTS (from primitive module)
# ==============================================================================

output "vertex_ai_bucket_name" {
  description = "Name of the GCS bucket for index data"
  value       = module.vertex_ai_index.bucket_name
}

output "vertex_ai_bucket_url" {
  description = "URL of the GCS bucket for index data"
  value       = module.vertex_ai_index.bucket_url
}

output "vertex_ai_index_id" {
  description = "ID of the Vertex AI index"
  value       = module.vertex_ai_index.index_id
}

output "vertex_ai_index_name" {
  description = "Name of the Vertex AI index"
  value       = module.vertex_ai_index.index_name
}

output "vertex_ai_endpoint_id" {
  description = "ID of the Vertex AI index endpoint"
  value       = module.vertex_ai_index.endpoint_id
}

output "vertex_ai_endpoint_name" {
  description = "Name of the Vertex AI index endpoint"
  value       = module.vertex_ai_index.endpoint_name
}

output "vertex_ai_public_endpoint_domain" {
  description = "Public endpoint domain name for internet-accessible queries"
  value       = module.vertex_ai_index.public_endpoint_domain
}

output "vertex_ai_deployed_index_id" {
  description = "ID of the deployed index"
  value       = module.vertex_ai_index.deployed_index_id
}

# Derived outputs for API calls
output "vertex_ai_endpoint_numeric_id" {
  description = "Numeric ID extracted from endpoint path (for API calls)"
  value       = module.vertex_ai_index.endpoint_numeric_id
}

output "vertex_ai_index_numeric_id" {
  description = "Numeric ID extracted from index path (for API calls)"
  value       = module.vertex_ai_index.index_numeric_id
}

output "vertex_ai_endpoint_subdomain" {
  description = "Subdomain extracted from public endpoint domain (for API calls)"
  value       = module.vertex_ai_index.endpoint_subdomain
}

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "proxy_runtime_sa_email" {
  description = "Email of the Apigee proxy runtime service account"
  value       = module.apigee.proxy_runtime_sa_email
}

output "apim_operator_sa_email" {
  description = "Email of the APIM Operator GSA (for KSA annotation: iam.gke.io/gcp-service-account)"
  value       = module.apigee.apim_operator_sa_email
}

output "apim_operator_sa_name" {
  description = "Full resource name of the APIM Operator GSA"
  value       = module.apigee.apim_operator_sa_name
}

output "semantic_cache_sa_email" {
  description = "Email address of the semantic cache service account"
  value       = module.apigee.proxy_runtime_sa_email
}
