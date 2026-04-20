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

data "google_project" "current" {
  project_id = var.project_id
}

# Service account for Cloud Run DLP ext_proc service
resource "google_service_account" "ext_proc" {
  project      = var.project_id
  account_id   = var.service_name
  display_name = "DLP ext_proc Service Account"
  description  = "Service account for DLP external processor"
}

# Grant ext_proc permissions to use Cloud DLP API
resource "google_project_iam_member" "ext_proc_dlp_user" {
  project = var.project_id
  role    = "roles/dlp.user"
  member  = "serviceAccount:${google_service_account.ext_proc.email}"
}

# Cloud Run service for DLP ext_proc
resource "google_cloud_run_v2_service" "ext_proc" {
  project  = var.project_id
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL" # Allow access from Service Extension infrastructure

  deletion_protection = false

  # Required for Service Extensions - ext_proc backends must allow unauthenticated access
  invoker_iam_disabled = true

  labels = var.labels

  template {
    service_account = google_service_account.ext_proc.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    timeout = "${var.timeout_seconds}s"

    containers {
      image = var.image

      ports {
        name           = "h2c"
        container_port = 8080
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "DLP_INFO_TYPES"
        value = var.dlp_info_types
      }

      env {
        name  = "DLP_MIN_LIKELIHOOD"
        value = var.dlp_min_likelihood
      }

      env {
        name  = "REDACT_REQUEST"
        value = tostring(var.redact_request)
      }

      env {
        name  = "REDACT_RESPONSE"
        value = tostring(var.redact_response)
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 3
        failure_threshold     = 3

        grpc {
          port = 8080
        }
      }

      liveness_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 10
        failure_threshold     = 3

        grpc {
          port = 8080
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Allow Compute System service agent to invoke ext_proc (for Load Balancer traffic)
resource "google_cloud_run_service_iam_member" "ext_proc_compute" {
  project  = var.project_id
  location = google_cloud_run_v2_service.ext_proc.location
  service  = google_cloud_run_v2_service.ext_proc.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"
}

# Allow Serverless Robot (Cloud Run service agent) to invoke ext_proc
resource "google_cloud_run_service_iam_member" "ext_proc_serverless" {
  project  = var.project_id
  location = google_cloud_run_v2_service.ext_proc.location
  service  = google_cloud_run_v2_service.ext_proc.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.current.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

# Allow DEP (Cloud Deploy Extension Platform) service agent to invoke ext_proc
resource "google_cloud_run_service_iam_member" "ext_proc_dep" {
  project  = var.project_id
  location = google_cloud_run_v2_service.ext_proc.location
  service  = google_cloud_run_v2_service.ext_proc.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dep.iam.gserviceaccount.com"
}

# Serverless NEG for Cloud Run service (ext_proc)
resource "google_compute_region_network_endpoint_group" "ext_proc_neg" {
  project               = var.project_id
  name                  = "${var.service_name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.ext_proc.name
  }
}

# Backend service for ext_proc
resource "google_compute_backend_service" "ext_proc" {
  project = var.project_id
  name    = "${var.service_name}-backend"

  protocol    = "HTTP2"
  timeout_sec = var.timeout_seconds

  backend {
    group = google_compute_region_network_endpoint_group.ext_proc_neg.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# LB Traffic Extension — attaches DLP ext_proc to load balancer forwarding rules
resource "google_network_services_lb_traffic_extension" "dlp_ext_proc" {
  project               = var.project_id
  name                  = "dlp-ext-proc-extension"
  location              = "global"
  description           = "DLP ext_proc service extension for PII redaction"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  forwarding_rules = var.forwarding_rules

  extension_chains {
    name = "dlp-redaction-chain"

    match_condition {
      cel_expression = "true"
    }

    extensions {
      name             = "dlp-ext-proc"
      authority        = "${var.service_name}-${data.google_project.current.number}.${var.region}.run.app"
      service          = google_compute_backend_service.ext_proc.id
      timeout          = "10s"
      supported_events = ["REQUEST_HEADERS"]
    }
  }
  depends_on = [google_cloud_run_v2_service.ext_proc]
  labels     = var.labels
}
