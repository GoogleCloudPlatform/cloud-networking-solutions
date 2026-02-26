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
 * GKE Node Service Account Module
 *
 * Creates a dedicated service account for GKE node pools with proper IAM roles.
 * Replaces the use of default Compute Engine service account with least-privilege access.
 */

# Create dedicated service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = var.service_account_name
  display_name = var.service_account_display_name
  description  = var.service_account_description
}

# Core GKE Node Permissions
# Provides: logging, monitoring, metrics, storage read, autoscaling metrics
resource "google_project_iam_member" "gke_node_service_account" {
  project = var.project_id
  role    = "roles/container.nodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Artifact Registry Reader - Pull container images
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Secret Manager Access - For Secret Manager CSI driver (Node SA)
resource "google_project_iam_member" "secret_manager_accessor" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Secret Manager Access - For Managed Secret Sync (GKE Service Agent)
resource "google_project_iam_member" "gke_service_agent_secret_manager_accessor" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com"
}

# Logging Writer - Enhanced logging
resource "google_project_iam_member" "logging_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Monitoring Metric Writer - Enhanced monitoring
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Storage Object Viewer - Read GCS objects (model downloads, etc.)
resource "google_project_iam_member" "storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Allow GKE service to use this service account
resource "google_service_account_iam_member" "gke_sa_user" {
  service_account_id = google_service_account.gke_nodes.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com"
}
