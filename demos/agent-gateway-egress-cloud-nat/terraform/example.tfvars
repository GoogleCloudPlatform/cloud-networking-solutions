# Copyright 2026 Google LLC
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

# ##############################################################################
# # REQUIRED — edit these three values before `terraform apply`.               #
# # Every variable below this block has a sensible default tuned for the demo. #
# ##############################################################################

# GCP project ID where all resources will be created.
project_id = "my-gcp-project-id"

# GCP organization ID (numeric).
organization_id = "123456789012"

# Members granted demo-wide roles
platform_admin_members = ["user:admin@example.com"]


# ##############################################################################
# # OPTIONAL — everything below this line has a default and is pre-tuned for   #
# # the demo. Override only when you know you need to.                         #
# ##############################################################################

# ==============================================================================
# MCP SERVICES (CLOUD RUN)
# ==============================================================================

# Map of MCP service name to deployment configuration. The map key becomes the
# Cloud Run service name AND the URL-mask token (e.g. legacy-dms ->
# legacy-dms.${mcp_internal_dns_zone.domain}). Adding a new service is a Cloud
# Run deploy plus one entry in this map (a DNS A record is added automatically).
# The `us-docker.pkg.dev/cloudrun/container/placeholder` image is a Google-
# provided stub; replace with your own image in Artifact Registry before the
# service handles real traffic (Skaffold deploys overwrite the image tag).
# min_instance_count = 1 keeps one warm instance per service. MCP tools/list
# runs at the start of every agent turn with a 5s initialize() timeout; a
# scale-to-zero cold start (~16-19s observed) trips that timeout and drops all
# MCP tools for the request. Set to 0 if you don't mind cold-start failures.
mcp_services = {
  bug-tickets-mcp = {
    source_dir     = "../src/bug-tickets-mcp"
    container_port = 8080
  }
}

# ==============================================================================
# MODEL ARMOR - AI Safety Screening
# ==============================================================================

# Enable Model Armor templates for AI safety filtering on LB traffic
enable_model_armor = true

# Enable a multi-region template for Gemini Enterprise
enable_model_armor_gemini_enterprise = true

# Prompt injection / jailbreak detection confidence threshold
# Options: LOW_AND_ABOVE, MEDIUM_AND_ABOVE, HIGH
model_armor_pi_jailbreak_confidence = "MEDIUM_AND_ABOVE"

# Sensitive Data Protection enforcement (ENABLED or DISABLED).
# When ENABLED, the model-armor module also creates a DLP inspect template
# (US_SOCIAL_SECURITY_NUMBER), a DLP de-identify template (replace with
# infoType), and binds the Model Armor service agent to roles/dlp.{user,reader}.
# The response Model Armor template's sdp_settings.advanced_config is wired to
# those DLP templates so SSNs in MCP responses are redacted in flight.
model_armor_sdp_enforcement = "ENABLED"

# ==============================================================================
# AGENT ENGINE - Vertex AI Agent Engine
# ==============================================================================

# Phase 2: set to true after running deploy_agent.py --build-only
# deploy_reasoning_engine = true

# ==============================================================================
# PSC INTERFACE - Private Service Connect for Agent Engine
# ==============================================================================

# Enable PSC Interface for Agent Engine to call back into the VPC.
# Creates network attachment, firewall rules, and IAM bindings. Independent
# of the master flag — leave true to give Agent Engine VPC reachability even
# when private networking is off.
enable_psc_interface = true

# ==============================================================================
# AGENT GATEWAY - Governance plane in front of MCP services
# ==============================================================================

# Name of the Agent Gateway resource (also used as a prefix for the network
# attachment, authz extensions, and authz policies).
agent_gateway_name = "agent-gateway"

# Dedicated subnet for the Agent Gateway PSC-I network attachment AND the
# relocated MCP internal LB VIP. Min /28, RFC1918, must NOT overlap
# 10.0.0.0/24, 10.0.1.0/24, or 10.0.2.0/24 (Agent Gateway egress restrictions).
agent_gateway_subnet_cidr = "10.20.0.0/28"

# ==============================================================================
# AGENT REGISTRY ENDPOINTS
# ==============================================================================

# Enable the Agent Registry endpoint provisioner
enable_agent_registry_endpoints = true
