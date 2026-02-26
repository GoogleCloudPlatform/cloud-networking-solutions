# Copyright 2025 Duncan James
# SPDX-License-Identifier: Apache-2.0

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
