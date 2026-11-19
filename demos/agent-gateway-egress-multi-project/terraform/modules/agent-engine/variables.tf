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



variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number (for Agent Identity IAM bindings)"
  type        = string
}

variable "organization_id" {
  description = "GCP organization ID (numeric). Required for Agent Identity IAM bindings."
  type        = string
}

variable "platform_admin_members" {
  description = "List of IAM members granted roles/aiplatform.user for Agent Engine access"
  type        = list(string)
  default     = []
}

variable "region" {
  description = "Region for the reasoning engine"
  type        = string
  default     = "us-central1"
}

variable "deploy_reasoning_engine" {
  description = "Deploy the bug-triage agent as a google_vertex_ai_reasoning_engine. Requires agent_gateway_id and a prebuilt agent_artifacts_manifest_path (run deploy_agent.py --build-only first)."
  type        = bool
  default     = false
}

variable "agent_gateway_id" {
  description = "Full Agent Gateway resource name (projects/.../agentGateways/<name>). Required when deploy_reasoning_engine = true. The reasoning engine binds ALL its egress to this gateway via agent_gateway_config.agent_to_anywhere_config."
  type        = string
  default     = null
}

variable "agent_artifacts_manifest_path" {
  description = "Path to the build-only manifest JSON produced by deploy_agent.py --build-only. Consumed by package_spec. Required when deploy_reasoning_engine = true."
  type        = string
  default     = null
}

variable "agent_staging_bucket" {
  description = "GCS bucket holding the artifacts staged by deploy_agent.py --build-only, as a gs:// URI. Defaults to gs://<project_id>-staging."
  type        = string
  default     = null

  validation {
    condition     = var.agent_staging_bucket == null || startswith(coalesce(var.agent_staging_bucket, "gs://"), "gs://")
    error_message = "agent_staging_bucket must be a gs:// URI."
  }
}

variable "agent_model" {
  description = "Gemini model id for the agent (env MODEL_NAME)."
  type        = string
  default     = "gemini-2.5-flash"
}

variable "model_endpoint_location" {
  description = "Vertex model endpoint location (env GOOGLE_CLOUD_LOCATION). 'global' hits the global Gemini endpoint."
  type        = string
  default     = "global"
}

variable "agent_display_name" {
  description = "Display name for the deployed reasoning engine."
  type        = string
  default     = "Software Bug Triage Agent"
}

variable "mcp_server_url" {
  description = "URL of the bug-tickets MCP server Cloud Run service (env BUG_TICKETS_MCP_URL). Passed to the agent container so it knows where to connect its MCPToolset."
  type        = string
  default     = null
}

variable "engine_depends_on" {
  description = "Opaque values the reasoning engine must wait for. Intended for the agent-gateway wait_for_gateway_id so the gateway is fully ready before the engine boots."
  type        = any
  default     = null
}
