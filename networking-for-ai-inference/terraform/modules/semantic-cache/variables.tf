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
  description = "The GCP region for resources"
  type        = string
}

# ==============================================================================
# OPTIONAL VARIABLES
# ==============================================================================

variable "vpc_id" {
  description = "VPC network ID (only used when Apigee VPC peering is enabled)"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# APIGEE CONFIGURATION (Object-based)
# ==============================================================================

variable "apigee" {
  description = <<-EOT
    Apigee configuration for semantic caching.

    Attributes:
    - organization: Apigee organization settings
    - envgroups: Map of environment group names to hostnames
    - environments: Map of environment configurations
    - instances: Map of instance configurations by region
    - endpoint_attachments: Map of PSC endpoint attachments

    Example:
      apigee = {
        organization = {
          billing_type        = "PAYG"
          disable_vpc_peering = true
        }
        envgroups = {
          prod = ["api.example.com"]
        }
        environments = {
          apis-prod = {
            display_name = "APIs Production"
            envgroups    = ["prod"]
            type         = "INTERMEDIATE"
            properties   = {
              "apigee-service-extension-enabled" = "true"
            }
          }
        }
        instances = {
          us-east4 = {
            environments = ["apis-prod"]
          }
        }
      }
  EOT
  type = object({
    organization = optional(object({
      display_name            = optional(string, "Apigee Organization")
      description             = optional(string, "Apigee Organization for Semantic Cache")
      billing_type            = optional(string, "PAYG")
      analytics_region        = optional(string)
      runtime_type            = optional(string, "CLOUD")
      disable_vpc_peering     = optional(bool, true)
      database_encryption_key = optional(string)
    }), {})

    envgroups = optional(map(list(string)), {})

    environments = optional(map(object({
      display_name = string
      description  = optional(string)
      envgroups    = list(string)
      type         = optional(string, "INTERMEDIATE")
      node_config = optional(object({
        min_node_count = optional(number)
        max_node_count = optional(number)
      }))
      properties = optional(map(string))
    })), {})

    instances = optional(map(object({
      environments                  = list(string)
      runtime_ip_cidr_range         = optional(string)
      troubleshooting_ip_cidr_range = optional(string)
      consumer_accept_list          = optional(list(string))
      disk_encryption_key           = optional(string)
    })), {})

    endpoint_attachments = optional(map(object({
      region             = string
      service_attachment = string
    })), {})
  })
  default = {}
}

# ==============================================================================
# VERTEX AI CONFIGURATION (Object-based)
# ==============================================================================

variable "vertex_ai" {
  description = <<-EOT
    Vertex AI vector search configuration for semantic caching.

    Attributes:
    - bucket_name: Custom GCS bucket name (auto-generated if null)
    - bucket_force_destroy: Allow bucket destruction with contents
    - index: Index configuration (dimensions, algorithm, etc.)
    - endpoint: Endpoint display name
    - deployed_index: Deployed index configuration (replicas, scaling)

    Example:
      vertex_ai = {
        index = {
          dimensions            = 768
          distance_measure_type = "DOT_PRODUCT_DISTANCE"
        }
        deployed_index = {
          min_replica_count = 1
          max_replica_count = 3
        }
      }
  EOT
  type = object({
    bucket_name          = optional(string)
    bucket_force_destroy = optional(bool, false)

    index = optional(object({
      display_name                 = optional(string, "Semantic Cache Index")
      description                  = optional(string, "Vector search index for semantic caching")
      dimensions                   = optional(number, 768)
      approximate_neighbors_count  = optional(number, 150)
      distance_measure_type        = optional(string, "DOT_PRODUCT_DISTANCE")
      feature_norm_type            = optional(string, "UNIT_L2_NORM")
      shard_size                   = optional(string, "SHARD_SIZE_SMALL")
      leaf_node_embedding_count    = optional(number, 1000)
      leaf_nodes_to_search_percent = optional(number, 7)
      contents_delta_path          = optional(string, "index-data")
      update_method                = optional(string, "STREAM_UPDATE")
    }), {})

    endpoint = optional(object({
      display_name = optional(string, "Semantic Cache Endpoint")
    }), {})

    deployed_index = optional(object({
      id                    = optional(string, "semantic_cache_deployed_v1")
      display_name          = optional(string, "Semantic Cache Deployed Index")
      min_replica_count     = optional(number, 1)
      max_replica_count     = optional(number, 3)
      enable_access_logging = optional(bool, false)
    }), {})
  })
  default = {}
}

# ==============================================================================
# SERVICE ACCOUNT CONFIGURATION
# ==============================================================================

variable "create_service_accounts" {
  description = "Create service accounts for Apigee and semantic cache operations"
  type        = bool
  default     = true
}

variable "create_apim_operator_iam" {
  description = "Create IAM bindings for Apigee APIM Operator"
  type        = bool
  default     = true
}

variable "enable_apim_workload_identity" {
  description = "Enable the Workload Identity IAM binding for the APIM Operator (requires GKE Workload Identity Pool to exist)"
  type        = bool
  default     = true
}

variable "apim_operator_namespace" {
  description = "Kubernetes namespace for APIM Operator service account"
  type        = string
  default     = "apim"
}

variable "apim_operator_ksa" {
  description = "Kubernetes service account name for APIM Operator"
  type        = string
  default     = "apim-ksa"
}
