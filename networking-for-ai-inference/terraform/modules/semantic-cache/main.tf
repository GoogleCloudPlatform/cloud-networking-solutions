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
 * Semantic Cache Wrapper Module
 *
 * A high-level module that composes Apigee + Vertex AI for semantic caching.
 * This module orchestrates the primitive modules to provide a complete
 * semantic caching solution.
 *
 * Key features:
 * - Apigee organization with environments and instances
 * - Vertex AI vector search index for semantic similarity
 * - Service accounts for proxy runtime and APIM Operator
 * - Optional DNS peering zones for internal resolution
 *
 * Removed components (use GKE ApigeeBackendResource instead):
 * - Internal load balancer (apigee-psc-lb.tf)
 * - PSC subnet (psc.tf)
 * - Vertex AI endpoint attachment (vertex-ai-endpoint-attachment.tf)
 */

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "google_project" "current" {
  project_id = var.project_id
}

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  common_labels = merge(var.labels, {
    purpose = "semantic-cache"
  })
}

# ==============================================================================
# APIGEE ORGANIZATION (Primitive Module)
# ==============================================================================

module "apigee" {
  source = "../apigee"

  project_id     = var.project_id
  project_number = data.google_project.current.number
  region         = var.region

  # Organization configuration
  organization = var.apigee.organization

  # VPC configuration (only used when disable_vpc_peering is false)
  vpc_id = var.vpc_id

  # Environments, envgroups, instances
  envgroups    = var.apigee.envgroups
  environments = var.apigee.environments
  instances    = var.apigee.instances

  # Endpoint attachments (for PSC connectivity)
  endpoint_attachments = var.apigee.endpoint_attachments

  # Service accounts
  create_service_accounts = var.create_service_accounts
  service_account_prefix  = "apigee"

  # APIM Operator
  create_apim_operator_iam      = var.create_apim_operator_iam
  enable_apim_workload_identity = var.enable_apim_workload_identity
  apim_operator_namespace       = var.apim_operator_namespace
  apim_operator_ksa             = var.apim_operator_ksa
}

# ==============================================================================
# VERTEX AI VECTOR INDEX (Primitive Module)
# ==============================================================================

module "vertex_ai_index" {
  source = "../vertex-ai-index"

  project_id  = var.project_id
  region      = var.region
  name_prefix = "semantic-cache"

  # GCS bucket configuration
  bucket_name          = var.vertex_ai.bucket_name
  bucket_force_destroy = var.vertex_ai.bucket_force_destroy

  # Index configuration
  index = var.vertex_ai.index

  # Endpoint configuration
  endpoint = var.vertex_ai.endpoint

  # Deployed index configuration
  deployed_index = var.vertex_ai.deployed_index

  labels = local.common_labels
}
