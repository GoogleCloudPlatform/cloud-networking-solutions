# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# CORE PROJECT CONFIGURATION
# ==============================================================================

# GCP project ID where all resources will be created
project_id = "my-gcp-project-id"

# GCP organization ID (numeric). Required for agent engine and org-level IAM.
organization_id = "123456789012"

# Members who receive platform-wide admin roles (e.g. discoveryengine.admin)
platform_admin_members = ["user:admin@example.com"]

# ==============================================================================
# DNS CONFIGURATION
# ==============================================================================

# Public DNS zone domain (must end with a dot)
# A Cloud DNS managed zone must already exist for this domain
dns_zone_domain = "demo.example.com."

# Enable Google Certificate Manager for automatic TLS certificates
# Provisions managed certs matching *.internal.<dns_zone_domain>
enable_certificate_manager = true

# ==============================================================================
# GKE CLUSTERS
# ==============================================================================

# Map of GKE clusters to create. Each cluster gets its own DNS subdomain.
clusters = {
  gateway-cluster = {
    # DNS subdomain prefix (creates <dns_domain>.internal.<dns_zone_domain>)
    dns_domain = "gateway"

    # Set to false to allow terraform destroy (true in production)
    deletion_protection = false
  }
}

# ==============================================================================
# MODEL ARMOR - AI Safety Screening
# ==============================================================================

# Enable Model Armor templates for AI safety filtering on LB traffic
enable_model_armor = true

# Enable a multi-region template for Gemini Enterprise
enable_model_armor_gemini_enterprise = true

# Members who receive modelarmor.admin and modelarmor.floorSettingsAdmin roles
model_armor_admin_members = ["user:admin@example.com"]

# Prompt injection / jailbreak detection confidence threshold
# Options: LOW_AND_ABOVE, MEDIUM_AND_ABOVE, HIGH
model_armor_pi_jailbreak_confidence = "MEDIUM_AND_ABOVE"

# Sensitive Data Protection enforcement (ENABLED or DISABLED)
# When ENABLED, Model Armor blocks requests/responses containing detected PII
model_armor_sdp_enforcement = "DISABLED"

# ==============================================================================
# AGENT ENGINE - Vertex AI Agent Engine
# ==============================================================================

# Enable Vertex AI Agent Engine infrastructure (IAM, networking)
enable_agent_engine = true

# Users granted roles/aiplatform.user for Agent Engine access
demo_users = ["user:developer@example.com"]

# ==============================================================================
# PSC INTERFACE - Private Service Connect for Agent Engine
# ==============================================================================

# Enable PSC Interface for Agent Engine to call back into the VPC
# Creates network attachment, firewall rules, and IAM bindings
enable_psc_interface = true

# Private DNS zone for resolving internal service hostnames from Agent Engine
psc_interface_dns_zone = {
  name   = "psc-interface-dns-zone"
  domain = "internal.demo.example.com." # Must match your internal service domain
}

# ==============================================================================
# APIGEE - API Management (optional)
# ==============================================================================

# Enable Apigee API Management Platform
# Set to true to provision Apigee org, environments, and instances
enable_apigee = false

# Apigee organization settings
apigee_organization = {
  display_name        = "MCP Gateway Apigee"
  description         = "Apigee organization for MCP gateway API management"
  billing_type        = "PAYG" # PAYG or SUBSCRIPTION
  analytics_region    = "us-central1"
  runtime_type        = "CLOUD" # CLOUD or HYBRID
  disable_vpc_peering = true    # true for PSC-based connectivity
}

# Apigee environment groups: map of group name to list of hostnames
apigee_envgroups = {
  prod = ["api.internal.demo.example.com", "internal.demo.example.com"]
}

# Apigee environments: map of environment name to configuration
apigee_environments = {
  apis-prod = {
    display_name = "APIs Production"
    description  = "Production environment for MCP gateway APIs"
    envgroups    = ["prod"]
    type         = "COMPREHENSIVE" # INTERMEDIATE or COMPREHENSIVE
    properties = {
      "apigee-service-extension-enabled" = "true" # Required for service extensions
    }
  }
}

# Apigee runtime instances by region
apigee_instances = {
  us-central1 = {
    environments = ["apis-prod"]
  }
}

# PSC endpoint attachments connecting Apigee to backend services
apigee_endpoint_attachments = {
  internal-gke-gateway = {
    region             = "us-central1"
    service_attachment = "projects/my-gcp-project-id/regions/us-central1/serviceAttachments/internal-gke-gateway"
  }
}

# Enable internal HTTPS load balancer for Apigee northbound traffic
apigee_enable_northbound_lb = true

# Internal DNS zone for Apigee southbound service resolution
apigee_internal_dns_zone = {
  name   = "apigee-internal-zone"
  domain = "internal.demo.example.com."
}

# Endpoint attachment key used for wildcard DNS A record
apigee_internal_dns_wildcard_endpoint_attachment = "internal-gke-gateway"

# DNS peering zones for Apigee to resolve backend service hostnames
apigee_dns_peering_zones = {
  apigee-internal-zone = {
    domain      = "internal.demo.example.com"
    description = "Apigee internal DNS zone peering for southbound connectivity"
  }
}
