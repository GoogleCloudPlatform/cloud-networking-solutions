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
# GCS BUCKET OUTPUTS
# ==============================================================================

output "bucket_name" {
  description = "Name of the GCS bucket for index data"
  value       = google_storage_bucket.index_data.name
}

output "bucket_url" {
  description = "URL of the GCS bucket for index data"
  value       = google_storage_bucket.index_data.url
}

# ==============================================================================
# INDEX OUTPUTS
# ==============================================================================

output "index_id" {
  description = "ID of the Vertex AI index"
  value       = google_vertex_ai_index.index.id
}

output "index_name" {
  description = "Name of the Vertex AI index"
  value       = google_vertex_ai_index.index.name
}

output "index_resource_name" {
  description = "Full resource name of the Vertex AI index"
  value       = google_vertex_ai_index.index.name
}

# ==============================================================================
# ENDPOINT OUTPUTS
# ==============================================================================

output "endpoint_id" {
  description = "ID of the Vertex AI index endpoint"
  value       = google_vertex_ai_index_endpoint.endpoint.id
}

output "endpoint_name" {
  description = "Name of the Vertex AI index endpoint"
  value       = google_vertex_ai_index_endpoint.endpoint.name
}

output "public_endpoint_domain" {
  description = "Public endpoint domain name for internet-accessible queries"
  value       = google_vertex_ai_index_endpoint.endpoint.public_endpoint_domain_name
}

# ==============================================================================
# DEPLOYED INDEX OUTPUTS
# ==============================================================================

output "deployed_index_id" {
  description = "ID of the deployed index"
  value       = google_vertex_ai_index_endpoint_deployed_index.deployed.deployed_index_id
}

output "deployed_index_name" {
  description = "Display name of the deployed index"
  value       = google_vertex_ai_index_endpoint_deployed_index.deployed.display_name
}

# ==============================================================================
# DERIVED OUTPUTS (for Apigee proxy configuration)
# ==============================================================================

output "endpoint_numeric_id" {
  description = "Numeric ID extracted from endpoint path (for API calls)"
  value       = element(split("/", google_vertex_ai_index_endpoint.endpoint.id), length(split("/", google_vertex_ai_index_endpoint.endpoint.id)) - 1)
}

output "index_numeric_id" {
  description = "Numeric ID extracted from index path (for API calls)"
  value       = element(split("/", google_vertex_ai_index.index.id), length(split("/", google_vertex_ai_index.index.id)) - 1)
}

output "endpoint_subdomain" {
  description = "Subdomain extracted from public endpoint domain (for API calls)"
  value       = element(split(".", google_vertex_ai_index_endpoint.endpoint.public_endpoint_domain_name), 0)
}
