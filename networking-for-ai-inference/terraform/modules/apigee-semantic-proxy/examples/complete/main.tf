# Copyright 2025 Duncan James
# SPDX-License-Identifier: Apache-2.0

# Complete example of deploying an Apigee semantic proxy with Vertex AI caching

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Deploy the semantic caching proxy
module "semantic_proxy" {
  source = "../../"

  # Proxy Configuration
  proxy_name          = var.proxy_name
  apigee_organization = var.apigee_organization
  apigee_environment  = var.apigee_environment

  # GCP Configuration
  project_id     = var.project_id
  project_number = var.project_number
  region         = var.region

  # Vertex AI Configuration (from vertex-ai-index module outputs)
  vertex_ai = {
    public_endpoint_domain = var.vertex_ai_public_endpoint_domain
    endpoint_numeric_id    = var.vertex_ai_endpoint_numeric_id
    index_numeric_id       = var.vertex_ai_index_numeric_id
    deployed_index_id      = var.vertex_ai_deployed_index_id
    embedding_model        = var.embedding_model
    similarity_threshold   = var.similarity_threshold
    ttl_seconds            = var.cache_ttl_seconds
  }
}

# Output the proxy details
output "proxy_endpoint" {
  description = "The full endpoint URL for the deployed proxy"
  value       = "https://${var.apigee_organization}-${var.apigee_environment}.apigee.net/${var.proxy_name}"
}

output "proxy_name" {
  description = "Name of the deployed proxy"
  value       = module.semantic_proxy.proxy_name
}

output "proxy_revision" {
  description = "Latest proxy revision"
  value       = module.semantic_proxy.proxy_revision
}
