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

# -----------------------------------------------------------------------------
# Reasoning engine deployment (optional). When deploy_reasoning_engine is true,
# this module deploys the mortgage agent as a google_vertex_ai_reasoning_engine
# instead of relying on the imperative src/mortgage-agent/deploy_agent.py.
# -----------------------------------------------------------------------------

variable "region" {
  description = "Region for the reasoning engine and MCP registry scope (distinct from the model endpoint location)."
  type        = string
  default     = "us-central1"
}

variable "deploy_reasoning_engine" {
  description = "Deploy the mortgage agent as a google_vertex_ai_reasoning_engine. Requires agent_gateway_id and a prebuilt agent_source_archive_path."
  type        = bool
  default     = false
}

variable "agent_gateway_id" {
  description = "Full Agent Gateway resource name (projects/.../agentGateways/<name>) the reasoning engine egresses through in AGENT_TO_ANYWHERE mode. Required when deploy_reasoning_engine is true."
  type        = string
  default     = null
}

variable "agent_artifacts_manifest_path" {
  description = "Path to the build-only manifest JSON (pickle/deps/requirements GCS URIs + python_version + class_methods) produced by `deploy_agent.py --build-only`. Consumed by package_spec. Required when deploy_reasoning_engine is true."
  type        = string
  default     = null
}

variable "agent_model" {
  description = "Gemini model id for the agent (env MODEL_NAME)."
  type        = string
  default     = "gemini-3.1-flash-lite-preview"
}

variable "model_endpoint_location" {
  description = "Vertex model endpoint location (env GOOGLE_CLOUD_LOCATION); 'global' hits the global Gemini endpoint. Intentionally decoupled from region."
  type        = string
  default     = "global"
}

variable "agent_display_name" {
  description = "Display name for the deployed reasoning engine."
  type        = string
  default     = "Mortgage Assistant Agent"
}
