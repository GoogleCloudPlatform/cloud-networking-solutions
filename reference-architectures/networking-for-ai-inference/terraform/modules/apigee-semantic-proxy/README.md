# Apigee Semantic Proxy Module

This Terraform module creates an Apigee API proxy with semantic caching capabilities using Vertex AI embeddings and vector search.

## Features

- **Semantic Cache Lookup:** Uses Vertex AI embeddings to check if similar prompts exist in the cache.
- **Semantic Cache Population:** Automatically caches new responses for future reuse.
- **Configurable Threshold:** Controls how similar prompts must be to trigger a cache hit.
- **TTL-based Expiration:** Automatically invalidates cache entries after a specified period.
- **Backend Forwarding:** Proxies requests to your configured backend services.

---

## Architecture

The proxy implements a two-stage caching mechanism:

1.  **Request Flow (Cache Lookup):**
    - The incoming request triggers the Semantic Cache Lookup policy.
    - If a cache hit occurs (similarity exceeds the threshold), the proxy returns the cached response.
    - If a cache miss occurs, the proxy forwards the request to the backend target.

2.  **Response Flow (Cache Population):**
    - The proxy captures the backend response and triggers the Semantic Cache Populate policy.
    - It stores the embedding and response pair in the Vertex AI vector index.
    - The proxy returns the response to the client.

---

## Prerequisites

Before you deploy this module, ensure you have:
- An active Apigee X organization and environment.
- The Vertex AI API enabled in your project.
- A Vertex AI Index and Index Endpoint already created.
- A service account with the `roles/aiplatform.user` and `roles/apigee.admin` roles.

---

## Usage Guide

### Basic Configuration

```hcl
module "semantic_proxy" {
  source = "./modules/apigee-semantic-proxy"

  proxy_name          = "semantic-cache"
  apigee_organization = "YOUR_ORG_ID"
  apigee_environment  = "prod"

  project_id     = "YOUR_PROJECT_ID"
  project_number = "YOUR_PROJECT_NUMBER"
  region         = "YOUR_REGION"

  index_endpoint_id            = "YOUR_INDEX_ENDPOINT_ID"
  deployed_index_id            = "semantic_cache_deployed"
  index_id                     = "YOUR_INDEX_ID"
  vertex_ai_endpoint_subdomain = "YOUR_SUBDOMAIN"

  backend_target = "http://YOUR_BACKEND_IP"

  similarity_threshold = 0.95
  cache_ttl_seconds    = 60
}
```

---

## Variables

| Variable | Type | Description | Default | Required |
|----------|------|-------------|---------|----------|
| `proxy_name` | `string` | The name of the Apigee API proxy and its base path. | - | Yes |
| `project_id` | `string` | The Google Cloud project ID. | - | Yes |
| `project_number` | `string` | The GCP project number (required for Vertex AI API URLs). | - | Yes |
| `region` | `string` | The GCP region for Vertex AI resources. | - | Yes |
| `apigee_organization` | `string` | The Apigee organization ID. | - | Yes |
| `apigee_environment` | `string` | The Apigee environment name for deployment. | - | Yes |
| `vertex_ai` | `object` | Vertex AI configuration for semantic cache policies (see below). | - | Yes |

### `vertex_ai` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `public_endpoint_domain` | `string` | The public endpoint domain from the vertex-ai-index module. | - (required) |
| `endpoint_numeric_id` | `string` | Numeric endpoint ID for API calls. | - (required) |
| `index_numeric_id` | `string` | Numeric index ID for API calls. | - (required) |
| `deployed_index_id` | `string` | The deployed index ID. | - (required) |
| `embedding_model` | `string` | The embedding model to use. | `"gemini-embedding-001"` |
| `similarity_threshold` | `number` | Similarity threshold for cache hits (0.0 to 1.0). | `0.95` |
| `ttl_seconds` | `number` | Cache entry time-to-live in seconds. | `600` |

---

## Outputs

| Output | Description |
|--------|-------------|
| `proxy_name` | The name of the created Apigee API proxy. |
| `base_path` | The base path where the proxy is accessible. |
| `deployment_id` | The ID of the Apigee API proxy deployment. |

---

## Troubleshooting

### Permission Denied during Cache Population
If cache population fails with a `PERMISSION_DENIED` error, ensure the Apigee proxy service account has the `roles/aiplatform.user` role in the project containing the Vertex AI index.

### Low Cache Hit Rate
If you notice a lower than expected cache hit rate, consider decreasing the `similarity_threshold`. For example, a threshold of `0.85` will match more varied prompts but may return less precise results.

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
