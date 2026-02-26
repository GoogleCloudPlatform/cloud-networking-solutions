# Copyright 2025 Duncan James
# SPDX-License-Identifier: Apache-2.0

variable "proxy_name" {
  description = "Name of the Apigee API proxy"
  type        = string
  default     = "semantic-cache"
}

variable "region" {
  description = "GCP region for Vertex AI resources"
  type        = string
  default     = "us-east4"
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number"
  type        = string
}

variable "apigee_organization" {
  description = "Apigee organization ID"
  type        = string
}

variable "apigee_environment" {
  description = "Apigee environment name for deployment"
  type        = string
  default     = "prod"
}

# ==============================================================================
# VERTEX AI CONFIGURATION (from vertex-ai-index module outputs)
# ==============================================================================

variable "vertex_ai_public_endpoint_domain" {
  description = "Public endpoint domain name for Vertex AI index (e.g., '1339103203.us-east4-875697927408.vdb.vertexai.goog')"
  type        = string
}

variable "vertex_ai_endpoint_numeric_id" {
  description = "Numeric ID of the Vertex AI index endpoint"
  type        = string
}

variable "vertex_ai_index_numeric_id" {
  description = "Numeric ID of the Vertex AI index"
  type        = string
}

variable "vertex_ai_deployed_index_id" {
  description = "ID of the deployed index"
  type        = string
}

variable "embedding_model" {
  description = "Vertex AI embedding model to use"
  type        = string
  default     = "gemini-embedding-001"
}

variable "similarity_threshold" {
  description = "Similarity threshold for semantic cache hits (0.0-1.0)"
  type        = number
  default     = 0.95
}

variable "cache_ttl_seconds" {
  description = "Time-to-live for cached responses in seconds"
  type        = number
  default     = 600
}
