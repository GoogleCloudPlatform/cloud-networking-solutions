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
 * Service Extension Primitive Module
 *
 * A standalone, reusable module for deploying ext_proc services on Cloud Run
 * with Load Balancer integration for service extensions (route or traffic).
 *
 * Key features:
 * - Cloud Run gRPC service deployment (HTTP/2 cleartext)
 * - Service account with proper IAM for LB service agents
 * - Regional backend service for ext_proc callouts
 * - Serverless NEG for Cloud Run integration
 * - Object-based configuration for clean variable structure
 *
 * Common use cases:
 * - Body-Based Routing (BBR) for model extraction
 * - Custom request/response transformation
 * - Header injection for routing decisions
 * - Content filtering and validation
 */

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "google_project" "current" {
  project_id = var.project_id
}

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  resource_prefix = "${var.name_prefix}-${var.service_name}"

  # Default environment variables for ext_proc services
  default_env_vars = {
    LOG_LEVEL = var.cloud_run.log_level
  }

  # Merge default and custom environment variables
  env_vars = merge(local.default_env_vars, var.cloud_run.environment_variables)

  common_labels = merge(var.labels, {
    purpose = "service-extension"
    service = var.service_name
  })
}

# ==============================================================================
# SERVICE ACCOUNT FOR EXT_PROC
# ==============================================================================

resource "google_service_account" "ext_proc" {
  count = var.create_service_account ? 1 : 0

  project      = var.project_id
  account_id   = "${local.resource_prefix}-extproc"
  display_name = "${var.service_name} ext_proc Service Account"
  description  = "Service account for ${var.service_name} ext_proc service extension"
}

# Logging Writer - for Cloud Logging
resource "google_project_iam_member" "ext_proc_logging" {
  count = var.create_service_account ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.ext_proc[0].email}"
}

# Monitoring Metric Writer - for Cloud Monitoring
resource "google_project_iam_member" "ext_proc_monitoring" {
  count = var.create_service_account ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.ext_proc[0].email}"
}

# ==============================================================================
# CLOUD RUN SERVICE - EXT_PROC (gRPC)
# ==============================================================================

resource "google_cloud_run_service" "ext_proc" {
  name     = local.resource_prefix
  project  = var.project_id
  location = var.region

  template {
    spec {
      # Service account for ext_proc
      service_account_name = var.create_service_account ? google_service_account.ext_proc[0].email : var.service_account_email

      # Request timeout for gRPC calls
      timeout_seconds = var.cloud_run.timeout_seconds

      # Container configuration
      containers {
        image = var.cloud_run.image

        # Command (optional) - direct attribute, not block
        command = var.cloud_run.command

        # Expose gRPC port (HTTP/2 cleartext)
        ports {
          name           = "h2c"
          container_port = var.cloud_run.port
        }

        # Resource limits
        resources {
          limits = {
            cpu    = var.cloud_run.cpu_limit
            memory = var.cloud_run.memory_limit
          }
        }

        # Environment variables
        dynamic "env" {
          for_each = local.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }
      }

      # Container concurrency (high for ext_proc)
      container_concurrency = var.cloud_run.concurrency
    }

    metadata {
      annotations = {
        # Autoscaling configuration
        "autoscaling.knative.dev/minScale" = tostring(var.cloud_run.min_instances)
        "autoscaling.knative.dev/maxScale" = tostring(var.cloud_run.max_instances)

        # Client name annotation
        "run.googleapis.com/client-name" = "terraform"

        # Execution environment (second generation for better performance)
        "run.googleapis.com/execution-environment" = "gen2"

        # Enable HTTP/2 for gRPC
        "run.googleapis.com/launch-stage" = "BETA"
      }

      labels = local.common_labels
    }
  }

  # Traffic routing - send 100% to latest revision
  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true

  metadata {
    annotations = {
      # Enable HTTP/2 end-to-end for gRPC
      "run.googleapis.com/ingress" = "internal-and-cloud-load-balancing"
      # Disable IAM invoker check - required for LB route extensions to call ext_proc
      "run.googleapis.com/invoker-iam-disabled" = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
    ]
  }
}

# ==============================================================================
# CLOUD RUN IAM - ALLOW LOAD BALANCER TO INVOKE
# ==============================================================================

# Allow Service Extensions Data Plane service agent
resource "google_cloud_run_service_iam_member" "ext_proc_invoker_dep" {
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_service.ext_proc.name

  role   = "roles/run.invoker"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dep.iam.gserviceaccount.com"
}

# Allow Network Actions service agent (handles LB traffic extensions)
resource "google_cloud_run_service_iam_member" "ext_proc_invoker_networkactions" {
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_service.ext_proc.name

  role   = "roles/run.invoker"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-networkactions.iam.gserviceaccount.com"
}

# Allow IAP service account (if IAP is being used)
resource "google_cloud_run_service_iam_member" "ext_proc_invoker_iap" {
  count = var.grant_iap_invoker ? 1 : 0

  project  = var.project_id
  location = var.region
  service  = google_cloud_run_service.ext_proc.name

  role   = "roles/run.invoker"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-iap.iam.gserviceaccount.com"
}

# Allow Compute Engine default service account as fallback
resource "google_cloud_run_service_iam_member" "ext_proc_invoker_compute" {
  count = var.grant_compute_invoker ? 1 : 0

  project  = var.project_id
  location = var.region
  service  = google_cloud_run_service.ext_proc.name

  role   = "roles/run.invoker"
  member = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# ==============================================================================
# SERVERLESS NEG FOR CLOUD RUN
# ==============================================================================

resource "google_compute_region_network_endpoint_group" "ext_proc" {
  count = var.create_backend_service ? 1 : 0

  name                  = "${local.resource_prefix}-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_service.ext_proc.name
  }
}

# ==============================================================================
# REGIONAL BACKEND SERVICE FOR EXT_PROC CALLOUTS
# ==============================================================================

resource "google_compute_region_backend_service" "ext_proc" {
  count = var.create_backend_service ? 1 : 0

  name                  = "${local.resource_prefix}-backend"
  project               = var.project_id
  region                = var.region
  protocol              = "HTTP2" # gRPC requires HTTP2
  load_balancing_scheme = var.backend_service.load_balancing_scheme
  timeout_sec           = var.backend_service.timeout_sec

  # Serverless NEG for Cloud Run ext_proc
  backend {
    group           = google_compute_region_network_endpoint_group.ext_proc[0].id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  # No health check for serverless NEG

  log_config {
    enable      = var.backend_service.enable_logging
    sample_rate = var.backend_service.log_sample_rate
  }

  description = "Regional backend service for ${var.service_name} ext_proc callouts"
}
