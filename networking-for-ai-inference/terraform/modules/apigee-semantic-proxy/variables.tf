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


variable "proxy_name" {
  description = "Name of the Apigee API proxy"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where the Apigee proxy will be deployed"
  type        = string
}

variable "project_number" {
  description = "GCP project number (required for Vertex AI API URLs)"
  type        = string
}

variable "region" {
  description = "GCP region for Vertex AI resources"
  type        = string
}

variable "apigee_organization" {
  description = "Apigee organization ID"
  type        = string
}

variable "apigee_environment" {
  description = "Apigee environment name for deployment"
  type        = string
}

# ==============================================================================
# VERTEX AI CONFIGURATION (from vertex-ai-index module outputs)
# ==============================================================================

variable "vertex_ai" {
  description = "Vertex AI configuration for semantic cache policies"
  type = object({
    # From vertex-ai-index module outputs
    public_endpoint_domain = string # e.g., "1339103203.us-east4-875697927408.vdb.vertexai.goog"
    endpoint_numeric_id    = string # e.g., "5369280316290629632"
    index_numeric_id       = string # e.g., "3304366693001723904"
    deployed_index_id      = string # e.g., "semantic_cache_deployed"

    # Policy configuration
    embedding_model      = optional(string, "gemini-embedding-001")
    similarity_threshold = optional(number, 0.95)
    ttl_seconds          = optional(number, 600)
  })
}
