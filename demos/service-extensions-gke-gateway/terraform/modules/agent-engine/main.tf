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

# =============================================================================
# Agent Identity IAM bindings
# Grants permissions to all Agent Engine agents in this project.
# See: https://docs.cloud.google.com/agent-builder/agent-engine/agent-identity
# =============================================================================

locals {
  agent_identity_principal = "principalSet://agents.global.org-${var.organization_id}.system.id.goog/attribute.platformContainer/aiplatform/projects/${var.project_number}"
}

resource "google_project_iam_member" "agent_identity_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_browser" {
  project = var.project_id
  role    = "roles/browser"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_express_user" {
  project = var.project_id
  role    = "roles/aiplatform.expressUser"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_api_registry_viewer" {
  project = var.project_id
  role    = "roles/cloudapiregistry.viewer"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_telemetry_writer" {
  project = var.project_id
  role    = "roles/telemetry.writer"
  member  = local.agent_identity_principal
}

# =============================================================================
# Demo user IAM bindings
# Grants roles/aiplatform.user to demo users.
# =============================================================================

resource "google_project_iam_member" "demo_user_aiplatform_user" {
  for_each = toset(var.demo_users)
  project  = var.project_id
  role     = "roles/aiplatform.user"
  member   = each.value
}
