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
 * Root Terraform Variables
 *
 * Input variables for the gateway infrastructure.
 * Covers foundation, networking, GKE, and DNS modules.
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
  description = "List of IAM members to grant platform-wide admin roles such as discoveryengine.admin (e.g. [\"user:admin@example.com\"])"
  type        = list(string)
  default     = []
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
  description = "Name of the subnet"
  type        = string
  default     = "gke-subnet-us-central1"
}

variable "pods_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary range for services"
  type        = string
  default     = "services"
}

variable "primary_subnet_cidr" {
  description = "CIDR range for the primary subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "CIDR range for GKE pods"
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "CIDR range for GKE services"
  type        = string
  default     = "10.8.0.0/20"
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
# DNS CONFIGURATION
# ==============================================================================

variable "dns_zone_domain" {
  description = "The domain name for the public DNS zone (must end with a dot, e.g., 'example.com.')"
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "The name of the existing Cloud DNS managed zone. If not provided, derived from dns_zone_domain."
  type        = string
  default     = null
}

variable "enable_certificate_manager" {
  description = "Enable Certificate Manager to create managed certificates for the DNS domain"
  type        = bool
  default     = false
}

# ==============================================================================
# SECRETS CONFIGURATION
# ==============================================================================

variable "enable_secret_manager" {
  description = "Enable Secret Manager integration for GKE nodes (grants secretAccessor role to node service account)"
  type        = bool
  default     = true
}

# ==============================================================================
# GKE CLUSTERS CONFIGURATION
# ==============================================================================

variable "clusters" {
  description = "Map of GKE cluster configurations. Each cluster can specify dns_domain, deletion_protection, and secret_sync_config for syncing secrets from Secret Manager."
  type = map(object({
    dns_domain          = string
    deletion_protection = optional(bool, true)
    secret_sync_config = optional(object({
      enabled = bool
      rotation_config = optional(object({
        enabled           = optional(bool)
        rotation_interval = optional(string)
      }))
    }))
  }))
  default = {
    gateway-cluster = {
      dns_domain          = "gateway"
      deletion_protection = true
    }
  }
}

# ==============================================================================
# MODEL ARMOR CONFIGURATION
# ==============================================================================

variable "enable_model_armor" {
  description = "Enable Model Armor template and IAM bindings"
  type        = bool
  default     = false
}

variable "model_armor_template_id" {
  description = "ID for the Model Armor template"
  type        = string
  default     = "default-safety-template"
}

variable "model_armor_rai_filters" {
  description = "RAI (Responsible AI) filter configurations. filter_type can be: SEXUALLY_EXPLICIT, HATE_SPEECH, HARASSMENT, DANGEROUS. confidence_level can be: LOW_AND_ABOVE, MEDIUM_AND_ABOVE, HIGH"
  type = list(object({
    filter_type      = string
    confidence_level = string
  }))
  default = [
    {
      filter_type      = "HATE_SPEECH"
      confidence_level = "MEDIUM_AND_ABOVE"
    },
    {
      filter_type      = "HARASSMENT"
      confidence_level = "MEDIUM_AND_ABOVE"
    },
    {
      filter_type      = "SEXUALLY_EXPLICIT"
      confidence_level = "MEDIUM_AND_ABOVE"
    }
  ]
}

variable "model_armor_sdp_enforcement" {
  description = "Sensitive Data Protection filter enforcement setting (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.model_armor_sdp_enforcement)
    error_message = "model_armor_sdp_enforcement must be ENABLED or DISABLED"
  }
}

variable "model_armor_pii_types" {
  description = "List of PII info types to detect and block"
  type        = list(string)
  default = [
    "US_SOCIAL_SECURITY_NUMBER",
    "CREDIT_CARD_NUMBER",
    "PHONE_NUMBER",
    "EMAIL_ADDRESS",
    "PASSPORT",
    "DATE_OF_BIRTH",
    "MEDICAL_RECORD_NUMBER",
    "IP_ADDRESS",
    "STREET_ADDRESS",
    "PERSON_NAME"
  ]
}

variable "model_armor_pi_jailbreak_enforcement" {
  description = "PI and jailbreak filter enforcement setting (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
}

variable "model_armor_pi_jailbreak_confidence" {
  description = "PI and jailbreak filter confidence level (LOW_AND_ABOVE, MEDIUM_AND_ABOVE, or HIGH)"
  type        = string
  default     = "LOW_AND_ABOVE"
  validation {
    condition     = contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_pi_jailbreak_confidence)
    error_message = "model_armor_pi_jailbreak_confidence must be one of: LOW_AND_ABOVE, MEDIUM_AND_ABOVE, HIGH"
  }
}

variable "model_armor_malicious_uri_enforcement" {
  description = "Malicious URI filter enforcement setting (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
}

variable "model_armor_admin_members" {
  description = "List of IAM members to grant modelarmor.admin and modelarmor.floorSettingsAdmin roles (e.g. [\"user:admin@example.com\"])"
  type        = list(string)
  default     = []
}

variable "enable_model_armor_mcp_floor_setting" {
  description = "Enable Model Armor floor setting for MCP server protection (BigQuery MCP)"
  type        = bool
  default     = true
}

variable "enable_model_armor_vertex_ai" {
  description = "Enable Model Armor integration with Vertex AI (floor setting + IAM)"
  type        = bool
  default     = false
}

variable "model_armor_vertex_ai_inspect_only" {
  description = "When true, Vertex AI uses INSPECT_ONLY mode; when false, uses INSPECT_AND_BLOCK"
  type        = bool
  default     = false
}

variable "model_armor_vertex_ai_cloud_logging" {
  description = "Enable Cloud Logging for Vertex AI Model Armor sanitization"
  type        = bool
  default     = true
}

variable "enable_model_armor_gemini_enterprise" {
  description = "Enable a multi-region Model Armor template for Gemini Enterprise"
  type        = bool
  default     = false
}

variable "model_armor_gemini_enterprise_template_id" {
  description = "ID for the Gemini Enterprise Model Armor template"
  type        = string
  default     = "gemini-enterprise-safety-template"
}

variable "model_armor_gemini_enterprise_location" {
  description = "Multi-region location for the Gemini Enterprise template"
  type        = string
  default     = "us"
  validation {
    condition     = contains(["us", "eu"], var.model_armor_gemini_enterprise_location)
    error_message = "model_armor_gemini_enterprise_location must be 'us' or 'eu'"
  }
}

# ==============================================================================
# DLP EXT_PROC CONFIGURATION
# ==============================================================================

variable "enable_dlp_ext_proc" {
  description = "Enable the DLP ext_proc service extension for PII redaction"
  type        = bool
  default     = false
}

variable "dlp_ext_proc_image" {
  description = "Container image URL for the DLP ext_proc service"
  type        = string
  default     = null
}

variable "dlp_ext_proc_info_types" {
  description = "Comma-separated DLP info types to detect (empty string uses application defaults)"
  type        = string
  default     = ""
}

variable "dlp_ext_proc_min_likelihood" {
  description = "Minimum detection likelihood for DLP findings"
  type        = string
  default     = "LIKELY"
}

variable "dlp_ext_proc_redact_request" {
  description = "Redact PII in request bodies"
  type        = bool
  default     = false
}

variable "dlp_ext_proc_redact_response" {
  description = "Redact PII in response bodies"
  type        = bool
  default     = true
}

variable "dlp_ext_proc_forwarding_rules" {
  description = "List of forwarding rule IDs to attach the DLP ext_proc traffic extension to"
  type        = list(string)
  default     = []
}

# ==============================================================================
# AGENT ENGINE DEMO CONFIGURATION
# ==============================================================================

variable "enable_agent_engine" {
  description = "Enable the Agent Engine demo (chat API + LB for token exchange)"
  type        = bool
  default     = false
}

variable "demo_users" {
  description = "List of user emails to grant roles/aiplatform.user for Agent Engine access"
  type        = list(string)
  default     = []
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
  description = "Private DNS zone for PSC Interface DNS peering"
  type = object({
    name   = optional(string, "psc-interface-dns-zone")
    domain = string
  })
  default = null
}

# ==============================================================================
# APIGEE CONFIGURATION
# ==============================================================================

variable "enable_apigee" {
  description = "Enable Apigee API Management Platform"
  type        = bool
  default     = false
}

variable "apigee_organization" {
  description = "Apigee organization configuration object"
  type = object({
    display_name            = optional(string, "Apigee Organization")
    description             = optional(string, "Apigee Organization for API Management")
    billing_type            = optional(string, "PAYG")
    analytics_region        = optional(string)
    runtime_type            = optional(string, "CLOUD")
    disable_vpc_peering     = optional(bool, true)
    database_encryption_key = optional(string)
  })
  default = {}
}

variable "apigee_envgroups" {
  description = "Map of Apigee environment group names to hostnames"
  type        = map(list(string))
  default     = {}
}

variable "apigee_environments" {
  description = "Map of Apigee environments with display_name, envgroups, type, and optional properties"
  type = map(object({
    display_name = string
    description  = optional(string)
    envgroups    = list(string)
    type         = optional(string, "INTERMEDIATE")
    node_config = optional(object({
      min_node_count = optional(number)
      max_node_count = optional(number)
    }))
    properties = optional(map(string))
  }))
  default = {}
}

variable "apigee_instances" {
  description = "Map of Apigee instances by region"
  type = map(object({
    environments                  = list(string)
    runtime_ip_cidr_range         = optional(string)
    troubleshooting_ip_cidr_range = optional(string)
    consumer_accept_list          = optional(list(string))
    disk_encryption_key           = optional(string)
  }))
  default = {}
}

variable "apigee_endpoint_attachments" {
  description = "Map of Apigee endpoint attachments for PSC connections"
  type = map(object({
    region             = string
    service_attachment = string
  }))
  default = {}
}

variable "apigee_vpc_id" {
  description = "VPC network ID for Apigee (only used when disable_vpc_peering is false)"
  type        = string
  default     = null
}

variable "apigee_create_service_accounts" {
  description = "Create service accounts for Apigee proxy runtime"
  type        = bool
  default     = true
}

variable "apigee_service_account_prefix" {
  description = "Prefix for Apigee service account names"
  type        = string
  default     = "apigee"
}

variable "apigee_create_apim_operator_iam" {
  description = "Create IAM bindings for Apigee APIM Operator"
  type        = bool
  default     = true
}

variable "apigee_enable_apim_workload_identity" {
  description = "Enable Workload Identity IAM binding for APIM Operator"
  type        = bool
  default     = false
}

variable "apigee_apim_operator_namespace" {
  description = "Kubernetes namespace for APIM Operator service account"
  type        = string
  default     = "apim"
}

variable "apigee_apim_operator_ksa" {
  description = "Kubernetes service account name for APIM Operator"
  type        = string
  default     = "apim-ksa"
}

variable "apigee_enable_northbound_lb" {
  description = "Enable Apigee northbound internal HTTPS load balancer via PSC"
  type        = bool
  default     = false
}

variable "apigee_dns_peering_zones" {
  description = "Map of DNS peering zones for Apigee southbound connectivity (domain, description only - project/network auto-injected)"
  type = map(object({
    domain      = string
    description = optional(string, "Terraform-managed Apigee DNS peering zone")
  }))
  default = {}
}

variable "apigee_internal_dns_zone" {
  description = "Apigee internal DNS zone config (created in networking module)"
  type = object({
    name   = optional(string, "apigee-internal-zone")
    domain = string
  })
  default = null
}

variable "apigee_internal_dns_wildcard_endpoint_attachment" {
  description = "Endpoint attachment key to use for the wildcard A record in the Apigee internal DNS zone"
  type        = string
  default     = null
}
