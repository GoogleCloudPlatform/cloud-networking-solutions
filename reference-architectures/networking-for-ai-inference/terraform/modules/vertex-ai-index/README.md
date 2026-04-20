# Vertex AI Index Module

This module provides a comprehensive solution for creating and managing vector search indexes and endpoints using Vertex AI. It enables semantic similarity search through highly configurable vector indexes, supporting machine learning and AI-driven search capabilities.

## Features

- **GCS Storage:** Create GCS buckets for index data storage.
- **Vector Search:** Configure Vertex AI vector search indexes.
- **Customizable Algorithms:** Set index dimensions and algorithms to meet your requirements.
- **Public Endpoints:** Deploy public index endpoints with internet accessibility.
- **Autoscaling:** Manage deployed index replicas with auto-scaling support.
- **Flexible Configuration:** Support for various distance measures and feature normalization types.

## Use Cases

- Semantic similarity search for embeddings.
- Recommendation systems.
- Advanced document retrieval.
- AI-powered search functionality.
- Content-based matching.

## Prerequisites

Before you use this module, ensure your environment meets the following requirements:
- Terraform (>= 1.0)
- Google Cloud Provider (>= 4.0)
- A Google Cloud project with the Vertex AI API enabled.

---

## Variables

| Name | Type | Description | Default | Required |
|------|------|-------------|---------|----------|
| `project_id` | `string` | The Google Cloud project ID. | - | Yes |
| `region` | `string` | The region for Vertex AI resources. | - | Yes |
| `name_prefix` | `string` | Prefix for resource names. | `"semantic-cache"` | No |
| `labels` | `map(string)` | Labels to apply to all resources. | `{}` | No |
| `bucket_name` | `string` | Name of the GCS bucket for index data. | Auto-generated | No |
| `bucket_force_destroy` | `bool` | Allow force destruction of the GCS bucket. | `false` | No |
| `index` | `object` | Vertex AI Index configuration (see below). | `{}` | No |
| `endpoint` | `object` | Vertex AI Index Endpoint configuration (see below). | `{}` | No |
| `deployed_index` | `object` | Deployed Index configuration (see below). | `{}` | No |

### `index` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `display_name` | `string` | Display name for the index. | `"Vector Search Index"` |
| `description` | `string` | Description for the index. | `"Vector search index for semantic similarity"` |
| `dimensions` | `number` | Number of dimensions for embeddings (768 for `gemini-embedding-001`). | `768` |
| `approximate_neighbors_count` | `number` | Number of approximate neighbors to return. | `150` |
| `distance_measure_type` | `string` | Distance algorithm (`DOT_PRODUCT_DISTANCE`, `COSINE_DISTANCE`, `L2_SQUARED_DISTANCE`). | `"DOT_PRODUCT_DISTANCE"` |
| `feature_norm_type` | `string` | Feature normalization (`UNIT_L2_NORM` or `NONE`). | `"UNIT_L2_NORM"` |
| `shard_size` | `string` | Shard size (`SHARD_SIZE_SMALL`, `SHARD_SIZE_MEDIUM`, `SHARD_SIZE_LARGE`). | `"SHARD_SIZE_SMALL"` |
| `leaf_node_embedding_count` | `number` | Number of embeddings per leaf node. | `1000` |
| `leaf_nodes_to_search_percent` | `number` | Percentage of leaf nodes to search. | `7` |
| `contents_delta_path` | `string` | Path within GCS bucket for index data. | `"index-data"` |
| `update_method` | `string` | Index update method (`STREAM_UPDATE` or `BATCH_UPDATE`). | `"STREAM_UPDATE"` |

### `endpoint` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `display_name` | `string` | Display name for the endpoint. | `"Vector Search Endpoint"` |

### `deployed_index` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `id` | `string` | ID for the deployed index. | `"deployed_index_v1"` |
| `display_name` | `string` | Display name for the deployed index. | `"Deployed Index"` |
| `min_replica_count` | `number` | Minimum replicas for auto-scaling (must be >= 1). | `1` |
| `max_replica_count` | `number` | Maximum replicas for auto-scaling. | `3` |
| `enable_access_logging` | `bool` | Enable access logging. | `false` |

---

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Name of the GCS bucket for index data. |
| `index_id` | ID of the Vertex AI index. |
| `endpoint_id` | ID of the Vertex AI index endpoint. |
| `public_endpoint_domain` | Public endpoint domain for internet-accessible queries. |
| `deployed_index_id` | ID of the deployed index. |
| `endpoint_numeric_id` | Numeric ID for endpoint API calls. |
| `index_numeric_id` | Numeric ID for index API calls. |
| `endpoint_subdomain` | Subdomain for API calls. |

---

## Usage Example

```hcl
module "semantic_cache_index" {
  source = "./modules/vertex-ai-index"

  project_id = "YOUR_PROJECT_ID"
  region     = "YOUR_REGION"

  index = {
    display_name                = "Semantic Search Index"
    dimensions                  = 768
    approximate_neighbors_count = 150
    distance_measure_type       = "DOT_PRODUCT_DISTANCE"
    leaf_node_embedding_count   = 1000
  }

  deployed_index = {
    min_replica_count = 1
    max_replica_count = 3
  }
}
```

## Configuration Details

### Index Configuration

- **Dimensions:** Vector embedding size (e.g., 768 for text embedding models).
- **Distance Measure Types:**
  - `DOT_PRODUCT_DISTANCE`
  - `COSINE_DISTANCE`
  - `L2_SQUARED_DISTANCE`
- **Feature Norm Types:**
  - `UNIT_L2_NORM`
  - `NONE`
- **Shard Sizes:**
  - `SHARD_SIZE_SMALL`
  - `SHARD_SIZE_MEDIUM`
  - `SHARD_SIZE_LARGE`

### Deployed Index Configuration

- Configurable minimum and maximum replica count.
- Auto-scaling support.
- Optional access logging.

### GCS Bucket

- Versioning enabled.
- Uniform bucket-level access.
- Optional force destroy.

## Endpoint Characteristics

- Public, internet-accessible endpoint.
- No VPC or Private Service Connect requirements.
- Generates a domain name for API interactions.

## Troubleshooting

- Verify the Vertex AI API is enabled in your project.
- Check network and firewall settings.
- Monitor index creation and deployment logs.
- Validate embedding dimensions and distance measure types.

## Recommended Embedding Models

- `gemini-embedding-001`: 768 dimensions (recommended). This is the default model used by the semantic cache proxy.
- `textembedding-gecko@003`: 768 dimensions (legacy).

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
