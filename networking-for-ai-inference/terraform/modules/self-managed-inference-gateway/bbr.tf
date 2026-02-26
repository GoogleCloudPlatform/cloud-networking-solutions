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
# BODY-BASED ROUTING (BBR) EXT_PROC SERVICE
# ==============================================================================
#
# This file composes with the service-extension module to deploy the BBR
# ext_proc gRPC service on Cloud Run. The BBR service:
# 1. Receives request headers and body from the load balancer
# 2. Extracts the 'model' parameter from the JSON request body
# 3. Injects X-Gateway-Model-Name header for routing decisions
#
# ==============================================================================

module "bbr_ext_proc" {
  count  = var.body_based_routing.enabled ? 1 : 0
  source = "../service-extension"

  project_id   = var.project_id
  region       = var.region
  service_name = "bbr"
  name_prefix  = var.name_prefix

  cloud_run = {
    image         = var.body_based_routing.ext_proc.image
    cpu_limit     = var.body_based_routing.ext_proc.cpu_limit
    memory_limit  = var.body_based_routing.ext_proc.memory_limit
    min_instances = var.body_based_routing.ext_proc.min_instances
    max_instances = var.body_based_routing.ext_proc.max_instances
    environment_variables = {
      MODEL_HEADER_NAME = var.body_based_routing.model_header_name
    }
  }

  backend_service = {
    load_balancing_scheme = "INTERNAL_MANAGED"
  }

  labels = local.common_labels
}
