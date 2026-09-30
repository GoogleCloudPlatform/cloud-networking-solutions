# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



/**
 * Root Terraform Variables
 *
 * Input variables for the Self Managed Ingress Gateway infrastructure.
 * Covers foundation, networking, MCP Cloud Run services, internal LB, and DNS.
 */

# ==============================================================================
# CORE PROJECT CONFIGURATION
# ==============================================================================

variable "consumer_project_id" {
  description = "Project ID hosting Tier 1 - External Gateway."
  type        = string
}

variable "producer_project_id" {
  description = "Project ID hosting Tier 2 - Internal Gateway."
  type        = string
}

variable "region" {
  description = "Region used by the producer gateway and PSC resources."
  type        = string
  default     = "us-central1"
}

variable "consumer_network_name" {
  description = "Tier 1 VPC network name."
  type        = string
  default     = "self-managed-ingress-consumer"
}

variable "producer_network_name" {
  description = "Tier 2 VPC network name."
  type        = string
  default     = "self-managed-ingress-producer"
}

# ==========================+===================================================
# AGENT ENGINE CONFIGURATION
# ==============================================================================

variable "reasoning_engine_id" {
  type = string
}

# ==========================+===================================================
# VALIDATION ONLY
# ==============================================================================

variable "demo_admin_user" {
  description = "User allowed to access the test VM through IAP."
  type        = string
}

# variable "project_id" {
#   description = "The Google Cloud project ID where the demo resources are created."
#   type        = string
# }

# variable "region" {
#   description = "The default region for the regional and private networking resources."
#   type        = string
#   default     = "us-central1"
# }

# variable "zone" {
#   description = "The default zone for destinations and zonal resources."
#   type        = string
#   default     = "us-central1-a"
# }

# variable "name_prefix" {
#   description = "Short prefix applied to created resources."
#   type        = string
#   default     = "smig"
# }

# variable "domain_name" {
#   description = "Public domain used by the front door. Example: example.com."
#   type        = string
#   default     = "example.com."
# }

# variable "agents" {
#   description = "Per-agent hostnames and request rewrite settings for the front door and regional internal gateways."
#   type = map(object({
#     host         = string
#     path_prefix  = string
#     rewrite_path = string
#     backend_host = string
#     backend_path = string
#     iap_enabled  = optional(bool, true)
#     model_armor  = optional(bool, false)
#   }))
#   default = {
#     agent_a = {
#       host         = "agent-a.example.com"
#       path_prefix  = "/chat"
#       rewrite_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-a:streamQuery"
#       backend_host = "us-central1-aiplatform.googleapis.com"
#       backend_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-a:streamQuery"
#       iap_enabled  = true
#       model_armor  = true
#     }
#     agent_b = {
#       host         = "agent-b.example.com"
#       path_prefix  = "/chat"
#       rewrite_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-b:streamQuery"
#       backend_host = "us-central1-aiplatform.googleapis.com"
#       backend_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-b:streamQuery"
#       iap_enabled  = true
#       model_armor  = false
#     }
#   }
# }

# variable "enable_tls" {
#   description = "If true, create a managed SSL certificate for the public front door."
#   type        = bool
#   default     = false
# }

# variable "enable_iap" {
#   description = "If true, attach an IAP policy to the per-agent regional backend service."
#   type        = bool
#   default     = true
# }

# variable "enable_model_armor" {
#   description = "Placeholder switch to surface the Model Armor / ext_proc integration in the design."
#   type        = bool
#   default     = true
# }

# variable "iap_member" {
#   description = "IAM member used to allow access through IAP. Example: user:alice@example.com"
#   type        = string
#   default     = "user:admin@example.com"
# }
