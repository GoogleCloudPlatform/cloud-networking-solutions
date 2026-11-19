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
 * Input variables for the gateway infrastructure.
 * Covers foundation, networking, MCP Cloud Run services, internal LB, and DNS.
 */

# ==============================================================================
# CORE PROJECT CONFIGURATION
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "gateway"
}

variable "organization_id" {
  description = "GCP organization ID (numeric). Required when agent engine is enabled."
  type        = string
  default     = null
}

variable "platform_admin_members" {
  description = "List of IAM members granted demo-wide roles: discoveryengine.admin; aiplatform.user when enable_agent_engine (e.g. [\"user:admin@example.com\"])"
  type        = list(string)
  default     = []
}

variable "cloudbuild_bucket_name" {
  description = "Override the Cloud Build source bucket name. Defaults to <project_id>_cloudbuild, which matches the bucket gcloud/Cloud Build SDKs auto-pick when no --gcs-source-staging-dir is passed; overriding the name breaks that convenience."
  type        = string
  default     = null
}

variable "cloudbuild_bucket_force_destroy" {
  description = "Allow Terraform to destroy the Cloud Build bucket even if it contains objects. Safe for demos; set false in production."
  type        = bool
  default     = true
}

# ==============================================================================
# NETWORKING CONFIGURATION
# ==============================================================================

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "gateway-vpc"
}

variable "subnet_name" {
  description = "Name of the primary subnet"
  type        = string
  default     = "mcp-subnet-us-central1"
}

variable "primary_subnet_cidr" {
  description = "CIDR range for the primary subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "proxy_subnet_cidr" {
  description = "CIDR range for the proxy-only subnet"
  type        = string
  default     = "10.9.0.0/24"
}

variable "psc_subnet_cidr" {
  description = "CIDR range for the Private Service Connect subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "gateway_scope" {
  description = "Gateway scope: 'regional' for regional internal gateway, or null to skip gateway provisioning"
  type        = string
  default     = "regional"
  validation {
    condition     = var.gateway_scope == null || contains(["regional"], var.gateway_scope)
    error_message = "gateway_scope must be 'regional' or null"
  }
}

# ==============================================================================
# MCP SERVICES (CLOUD RUN) CONFIGURATION
# ==============================================================================

variable "mcp_services" {
  description = "Map of MCP Cloud Run services to deploy. The key becomes the Cloud Run service name and part of the container tag."
  type = map(object({
    source_dir         = optional(string)
    image              = optional(string)
    container_port     = optional(number, 8080)
    otel_service_name  = optional(string)
    min_instance_count = optional(number, 1)
    max_instance_count = optional(number, 5)
    cpu                = optional(string, "1")
    memory             = optional(string, "512Mi")
    env                = optional(map(string), {})
  }))
  default = {
    "bug-tickets-mcp" = {
      source_dir     = "../src/bug-tickets-mcp"
      container_port = 8080
    }
  }
}

variable "mcp_lb_protocol" {
  description = <<-EOT
    Front-end protocol for the MCP internal Application LB. With HTTPS, the LB
    serves a Google-managed regional cert for *.mcp.<dns_zone_domain> when
    enable_certificate_manager = true and gateway_scope = "regional"; otherwise
    it falls back to an auto-generated self-signed cert for *.<mcp_internal_dns_zone.domain>
    (note: not validatable by Agent Gateway today).

    Only used when `enable_cloud_run_private_networking = true` (the LB itself
    is gated by that flag).
  EOT
  type        = string
  default     = "HTTPS"
  validation {
    condition     = contains(["HTTP", "HTTPS"], var.mcp_lb_protocol)
    error_message = "mcp_lb_protocol must be HTTP or HTTPS."
  }
}

# ==============================================================================
# AGENT ENGINE DEMO CONFIGURATION
# ==============================================================================

variable "deploy_reasoning_engine" {
  description = "Deploy the bug-triage reasoning engine. Requires running deploy_agent.py --build-only first to produce the artifact manifest."
  type        = bool
  default     = false
}

variable "agent_artifacts_manifest_path" {
  description = "Path to the build manifest JSON produced by deploy_agent.py --build-only. Defaults to <repo>/build/agent_artifacts.json."
  type        = string
  default     = null
}

variable "agent_staging_bucket" {
  description = "GCS bucket for agent artifacts (gs:// URI). Defaults to gs://<project_id>-staging."
  type        = string
  default     = null

  validation {
    condition     = var.agent_staging_bucket == null || startswith(coalesce(var.agent_staging_bucket, "gs://"), "gs://")
    error_message = "agent_staging_bucket must be a gs:// URI."
  }
}

variable "agent_model" {
  description = "Gemini model ID for the bug-triage agent."
  type        = string
  default     = "gemini-2.5-flash"
}

variable "model_endpoint_location" {
  description = "Vertex AI model endpoint location (GOOGLE_CLOUD_LOCATION env). Use a regional value (e.g. 'us-central1') so the genai SDK uses a regional endpoint routable via private.googleapis.com."
  type        = string
  default     = "us-central1"
}

variable "agent_display_name" {
  description = "Display name for the deployed reasoning engine."
  type        = string
  default     = "Software Bug Triage Agent"
}

variable "agent_gateway_name" {
  description = "Name of the Agent Gateway resource."
  type        = string
  default     = "agent-gateway"
}

# ==============================================================================
# PSC INTERFACE CONFIGURATION
# ==============================================================================

variable "enable_psc_interface" {
  description = "Enable PSC Interface for Vertex AI Agent Engine (network attachment, firewall, IAM)"
  type        = bool
  default     = false
}

variable "psc_interface_subnet_cidr" {
  description = "CIDR for the PSC Interface subnet (min /28, must not overlap with psc_subnet_cidr)"
  type        = string
  default     = "10.11.0.0/28"
}

variable "psc_interface_dns_zone" {
  description = "Private DNS zone for PSC Interface DNS peering. `domain` MUST end with a trailing dot."
  type = object({
    name   = optional(string, "psc-interface-dns-zone")
    domain = string
  })
  default = null
  validation {
    condition     = var.psc_interface_dns_zone == null || endswith(var.psc_interface_dns_zone.domain, ".")
    error_message = "psc_interface_dns_zone.domain must end with a trailing dot (e.g. \"mcp.example.com.\")."
  }
}

# ==============================================================================
# AGENT GATEWAY CONFIGURATION
# ==============================================================================

variable "agent_gateway_subnet_cidr" {
  description = "CIDR for the Agent Gateway dedicated subnet. Min /28, RFC1918, must not overlap 10.0.0.0/24, 10.0.1.0/24, or 10.0.2.0/24 (Agent Gateway egress restrictions)."
  type        = string
  default     = "10.20.0.0/28"
}

# ==============================================================================
# AGENT REGISTRY ENDPOINT CONFIGURATION
# ==============================================================================

variable "enable_agent_registry_endpoints" {
  description = "Enable the Agent Registry endpoint provisioner (registers Google API and custom service endpoints)"
  type        = bool
  default     = false
}

# ==============================================================================
# AUDIT LOGGING
# ==============================================================================

variable "logging_data_access" {
  description = "Data access audit log configuration passed to the foundation module. Defaults to ADMIN_READ + DATA_READ + DATA_WRITE for the special 'allServices' key (project-wide audit logging across every API). Override per-service to scope down or to exempt members."
  type = map(object({
    ADMIN_READ = optional(object({ exempted_members = optional(list(string), []) }))
    DATA_READ  = optional(object({ exempted_members = optional(list(string), []) }))
    DATA_WRITE = optional(object({ exempted_members = optional(list(string), []) }))
  }))
  default = {
    "allServices" = {
      ADMIN_READ = {}
      DATA_READ  = {}
      DATA_WRITE = {}
    }
  }
  nullable = false
}
