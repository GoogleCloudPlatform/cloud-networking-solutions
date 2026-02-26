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
# REQUIRED VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for Vertex AI resources"
  type        = string
}

# ==============================================================================
# NAMING AND LABELING
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "semantic-cache"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# GCS BUCKET CONFIGURATION
# ==============================================================================

variable "bucket_name" {
  description = "Name of the GCS bucket for index data. If null, auto-generated from project_id and name_prefix."
  type        = string
  default     = null
}

variable "bucket_force_destroy" {
  description = "Allow force destruction of the GCS bucket"
  type        = bool
  default     = false
}

# ==============================================================================
# INDEX CONFIGURATION
# ==============================================================================

variable "index" {
  description = <<-EOT
    Vertex AI Index configuration.

    Attributes:
    - display_name: Display name for the index
    - description: Description for the index
    - dimensions: Number of dimensions for embeddings (768 for text-embedding models)
    - approximate_neighbors_count: Number of approximate neighbors to return
    - distance_measure_type: DOT_PRODUCT_DISTANCE, COSINE_DISTANCE, L2_SQUARED_DISTANCE
    - feature_norm_type: UNIT_L2_NORM or NONE
    - shard_size: SHARD_SIZE_SMALL, SHARD_SIZE_MEDIUM, SHARD_SIZE_LARGE
    - leaf_node_embedding_count: Number of embeddings per leaf node
    - leaf_nodes_to_search_percent: Percentage of leaf nodes to search
    - contents_delta_path: Path within GCS bucket for index data
    - update_method: STREAM_UPDATE or BATCH_UPDATE
  EOT
  type = object({
    display_name                 = optional(string, "Vector Search Index")
    description                  = optional(string, "Vector search index for semantic similarity")
    dimensions                   = optional(number, 768)
    approximate_neighbors_count  = optional(number, 150)
    distance_measure_type        = optional(string, "DOT_PRODUCT_DISTANCE")
    feature_norm_type            = optional(string, "UNIT_L2_NORM")
    shard_size                   = optional(string, "SHARD_SIZE_SMALL")
    leaf_node_embedding_count    = optional(number, 1000)
    leaf_nodes_to_search_percent = optional(number, 7)
    contents_delta_path          = optional(string, "index-data")
    update_method                = optional(string, "STREAM_UPDATE")
  })
  default = {}

  validation {
    condition = contains(
      ["DOT_PRODUCT_DISTANCE", "COSINE_DISTANCE", "L2_SQUARED_DISTANCE"],
      var.index.distance_measure_type
    )
    error_message = "index.distance_measure_type must be one of: DOT_PRODUCT_DISTANCE, COSINE_DISTANCE, L2_SQUARED_DISTANCE"
  }

  validation {
    condition     = contains(["UNIT_L2_NORM", "NONE"], var.index.feature_norm_type)
    error_message = "index.feature_norm_type must be UNIT_L2_NORM or NONE"
  }

  validation {
    condition = contains(
      ["SHARD_SIZE_SMALL", "SHARD_SIZE_MEDIUM", "SHARD_SIZE_LARGE"],
      var.index.shard_size
    )
    error_message = "index.shard_size must be one of: SHARD_SIZE_SMALL, SHARD_SIZE_MEDIUM, SHARD_SIZE_LARGE"
  }

  validation {
    condition     = contains(["STREAM_UPDATE", "BATCH_UPDATE"], var.index.update_method)
    error_message = "index.update_method must be STREAM_UPDATE or BATCH_UPDATE"
  }
}

# ==============================================================================
# ENDPOINT CONFIGURATION
# ==============================================================================

variable "endpoint" {
  description = <<-EOT
    Vertex AI Index Endpoint configuration.

    Attributes:
    - display_name: Display name for the endpoint
  EOT
  type = object({
    display_name = optional(string, "Vector Search Endpoint")
  })
  default = {}
}

# ==============================================================================
# DEPLOYED INDEX CONFIGURATION
# ==============================================================================

variable "deployed_index" {
  description = <<-EOT
    Deployed Index configuration.

    Attributes:
    - id: ID for the deployed index
    - display_name: Display name for the deployed index
    - min_replica_count: Minimum number of replicas for auto-scaling
    - max_replica_count: Maximum number of replicas for auto-scaling
    - enable_access_logging: Enable access logging for the deployed index
  EOT
  type = object({
    id                    = optional(string, "deployed_index_v1")
    display_name          = optional(string, "Deployed Index")
    min_replica_count     = optional(number, 1)
    max_replica_count     = optional(number, 3)
    enable_access_logging = optional(bool, false)
  })
  default = {}

  validation {
    condition     = var.deployed_index.min_replica_count >= 1
    error_message = "deployed_index.min_replica_count must be at least 1"
  }

  validation {
    condition     = var.deployed_index.max_replica_count >= var.deployed_index.min_replica_count
    error_message = "deployed_index.max_replica_count must be >= min_replica_count"
  }
}
