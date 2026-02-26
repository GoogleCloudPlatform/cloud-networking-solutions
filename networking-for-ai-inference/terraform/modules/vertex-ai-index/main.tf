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

/**
 * Vertex AI Index Primitive Module
 *
 * A standalone, reusable module for Vertex AI vector search infrastructure.
 * Creates vector index, endpoint, and deployed index for semantic similarity search.
 *
 * Key features:
 * - GCS bucket for index data storage
 * - Vertex AI Index with configurable dimensions and algorithm
 * - Public Index Endpoint (internet-accessible)
 * - Auto-scaling deployed index
 * - Object-based configuration for clean variable structure
 */

# ==============================================================================
# GCS BUCKET FOR INDEX DATA
# ==============================================================================

resource "google_storage_bucket" "index_data" {
  project       = var.project_id
  name          = var.bucket_name != null ? var.bucket_name : "${var.project_id}-${var.name_prefix}-index"
  location      = var.region
  force_destroy = var.bucket_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = merge(var.labels, {
    purpose = "vertex-ai-index-data"
  })
}

# ==============================================================================
# VERTEX AI INDEX
# ==============================================================================

resource "google_vertex_ai_index" "index" {
  project      = var.project_id
  region       = var.region
  display_name = var.index.display_name
  description  = var.index.description

  metadata {
    contents_delta_uri = "gs://${google_storage_bucket.index_data.name}/${var.index.contents_delta_path}"

    config {
      dimensions                  = var.index.dimensions
      approximate_neighbors_count = var.index.approximate_neighbors_count
      distance_measure_type       = var.index.distance_measure_type
      feature_norm_type           = var.index.feature_norm_type
      shard_size                  = var.index.shard_size

      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count    = var.index.leaf_node_embedding_count
          leaf_nodes_to_search_percent = var.index.leaf_nodes_to_search_percent
        }
      }
    }
  }

  index_update_method = var.index.update_method

  labels = merge(var.labels, {
    purpose = var.name_prefix
  })

  depends_on = [google_storage_bucket.index_data]
}

# ==============================================================================
# VERTEX AI INDEX ENDPOINT (PUBLIC)
# ==============================================================================

resource "google_vertex_ai_index_endpoint" "endpoint" {
  display_name = var.endpoint.display_name
  region       = var.region
  project      = var.project_id

  # No private_service_connect_config block = publicly accessible endpoint
  # Public endpoints are accessible via the internet without VPC/PSC requirements

  labels = merge(var.labels, {
    purpose = "${var.name_prefix}-endpoint"
  })
}

# ==============================================================================
# DEPLOYED INDEX
# ==============================================================================

resource "google_vertex_ai_index_endpoint_deployed_index" "deployed" {
  index_endpoint        = google_vertex_ai_index_endpoint.endpoint.id
  index                 = google_vertex_ai_index.index.id
  deployed_index_id     = var.deployed_index.id
  display_name          = var.deployed_index.display_name
  enable_access_logging = var.deployed_index.enable_access_logging

  automatic_resources {
    min_replica_count = var.deployed_index.min_replica_count
    max_replica_count = var.deployed_index.max_replica_count
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }

  depends_on = [
    google_vertex_ai_index_endpoint.endpoint,
    google_vertex_ai_index.index
  ]
}
