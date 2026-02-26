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
 * Foundation Module
 *
 * Enables required Google Cloud APIs and sets quota preferences.
 * This module should be applied first before any other infrastructure.
 */

module "project" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v53.0.0"
  name          = var.project_id
  project_reuse = {} # Use existing project

  services = [for s in var.enabled_services : s if s != "aiplatform.googleapis.com"]

  # NOTE: GPU quotas must be requested manually via GCP Console.
  # The Cloud Foundation Fabric quota feature requires the Service Usage Consumer
  # API which may not be available in all projects. Request quotas at:
  # https://console.cloud.google.com/iam-admin/quotas
}

# Ensure Service Extensions service identity exists
# This is required for IAM bindings in model-armor module
resource "google_project_service_identity" "network_services" {
  provider = google-beta
  project  = var.project_id
  service  = "networkservices.googleapis.com"

  depends_on = [module.project]
}

# Enable Vertex AI API explicitly to control order and avoid race conditions
# in the project module's IAM bindings
resource "google_project_service" "aiplatform" {
  project            = module.project.project_id
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

# Ensure Vertex AI service identity exists
# This must happen after the API is enabled
resource "google_project_service_identity" "aiplatform" {
  provider = google-beta
  project  = module.project.project_id
  service  = "aiplatform.googleapis.com"

  depends_on = [google_project_service.aiplatform]
}
