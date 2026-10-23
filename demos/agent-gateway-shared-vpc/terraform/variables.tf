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

# -----------------------------------------------------------------------------
# Core projects / region
# -----------------------------------------------------------------------------

variable "governance_project_id" {
  description = "GCP project ID for the Governance (Service) project hosting Agent Gateway, Agent Registry, Model Armor, MCP Cloud Run, and Agent Runtime."
  type        = string
}

variable "networking_project_id" {
  description = "GCP project ID for the Networking (Host) project hosting the Shared VPC, subnets, SWP, Cloud NAT, and DNS zones."
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "organization_id" {
  description = "GCP organization ID (numeric). Required for Agent Identity IAM principal set construction."
  type        = string
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Short RFC1035-compatible prefix for all resource names (1–21 lowercase letters, digits, or hyphens; must start with a letter)."
  type        = string
  default     = "agw-svpc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.name_prefix))
    error_message = "name_prefix must be 1–21 chars: lowercase letters, digits, hyphens; must start with a letter."
  }
}

variable "vpc_name" {
  description = "Name of the Shared VPC network in the Networking project"
  type        = string
  default     = "agw-svpc-network"
}

variable "subnet_name" {
  description = "Name of the primary subnet in the Shared VPC"
  type        = string
  default     = "agw-svpc-subnet"
}

# -----------------------------------------------------------------------------
# CIDR ranges
# -----------------------------------------------------------------------------

variable "primary_subnet_cidr" {
  description = "CIDR for the primary subnet in the Shared VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "agent_gateway_subnet_cidr" {
  description = "CIDR for the Agent Gateway PSC-I dedicated subnet in the Shared VPC. Must be /26 or larger."
  type        = string
  default     = "10.20.0.0/26"
}

variable "swp_proxy_subnet_cidr" {
  description = "CIDR for the Secure Web Proxy proxy-only subnet (purpose=REGIONAL_MANAGED_PROXY) in the Shared VPC."
  type        = string
  default     = "10.30.0.0/24"
}

# -----------------------------------------------------------------------------
# Cloud Build (for the bug-tickets-mcp container image in Governance project)
# -----------------------------------------------------------------------------

variable "cloudbuild_bucket_name" {
  description = "Name of the GCS bucket used for Cloud Build source uploads. Defaults to <governance_project_id>-<name_prefix>-cloudbuild."
  type        = string
  default     = null
}

variable "cloudbuild_bucket_force_destroy" {
  description = "Allow Terraform to destroy the Cloud Build bucket even if it contains objects. Safe for demos; set false in production."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# MCP services (the bug-tickets-mcp Cloud Run service in Governance project)
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Agent Gateway & Engine (Governance project)
# -----------------------------------------------------------------------------

variable "agent_gateway_name" {
  description = "Name of the Agent Gateway resource."
  type        = string
  default     = "agent-gateway"
}

variable "platform_admin_members" {
  description = "IAM members (e.g. user:foo@example.com) granted roles/aiplatform.user and admin roles"
  type        = list(string)
  default     = []
}

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
  description = "GCS bucket for agent artifacts (gs:// URI). Defaults to gs://<governance_project_id>-staging."
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
  description = "Vertex AI model endpoint location (GOOGLE_CLOUD_LOCATION env)."
  type        = string
  default     = "us-central1"
}

variable "agent_display_name" {
  description = "Display name for the deployed reasoning engine."
  type        = string
  default     = "Software Bug Triage Agent"
}

# -----------------------------------------------------------------------------
# Model Armor (Governance project)
# -----------------------------------------------------------------------------

variable "enable_model_armor" {
  description = "Set to true to deploy Model Armor templates and guardrails in the Governance project."
  type        = bool
  default     = true
}

variable "model_armor_request_template_id" {
  description = "Model Armor request template ID."
  type        = string
  default     = "agw-svpc-request-template"
}

variable "model_armor_response_template_id" {
  description = "Model Armor response template ID."
  type        = string
  default     = "agw-svpc-response-template"
}

variable "model_armor_rai_filters" {
  description = "Responsible AI filters for Model Armor templates."
  type = list(object({
    filter_type      = string
    confidence_level = string
  }))
  default = [
    {
      filter_type      = "HATE_SPEECH"
      confidence_level = "LOW_AND_ABOVE"
    },
    {
      filter_type      = "HARASSMENT"
      confidence_level = "LOW_AND_ABOVE"
    },
    {
      filter_type      = "SEXUALLY_EXPLICIT"
      confidence_level = "LOW_AND_ABOVE"
    },
    {
      filter_type      = "DANGEROUS"
      confidence_level = "LOW_AND_ABOVE"
    }
  ]
}

variable "model_armor_pi_jailbreak_enforcement" {
  description = "Prompt injection and jailbreak filter enforcement."
  type        = string
  default     = "ENABLED"
}

variable "model_armor_pi_jailbreak_confidence" {
  description = "Prompt injection and jailbreak confidence level threshold."
  type        = string
  default     = "MEDIUM_AND_ABOVE"
}

variable "model_armor_malicious_uri_enforcement" {
  description = "Malicious URI filter enforcement."
  type        = string
  default     = "ENABLED"
}

variable "model_armor_sdp_enforcement" {
  description = "Sensitive Data Protection (SDP) enforcement mode (ENABLED or DISABLED)."
  type        = string
  default     = "DISABLED"
}

variable "model_armor_pii_types" {
  description = "List of info types for SDP DLP inspect and redact templates."
  type        = list(string)
  default     = ["US_SOCIAL_SECURITY_NUMBER"]
}

# -----------------------------------------------------------------------------
# Audit logging
# -----------------------------------------------------------------------------

variable "logging_data_access" {
  description = "Data access audit log configuration."
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
