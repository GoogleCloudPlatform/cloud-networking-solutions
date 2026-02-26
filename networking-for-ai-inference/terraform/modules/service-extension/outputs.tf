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

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "service_account_email" {
  description = "Email of the ext_proc service account"
  value       = var.create_service_account ? google_service_account.ext_proc[0].email : var.service_account_email
}

output "service_account_id" {
  description = "ID of the ext_proc service account"
  value       = var.create_service_account ? google_service_account.ext_proc[0].id : null
}

# ==============================================================================
# CLOUD RUN SERVICE OUTPUTS
# ==============================================================================

output "cloud_run_service_name" {
  description = "Name of the Cloud Run ext_proc service"
  value       = google_cloud_run_service.ext_proc.name
}

output "cloud_run_service_id" {
  description = "ID of the Cloud Run ext_proc service"
  value       = google_cloud_run_service.ext_proc.id
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run ext_proc service"
  value       = google_cloud_run_service.ext_proc.status[0].url
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run ext_proc service"
  value       = google_cloud_run_service.ext_proc.location
}

output "cloud_run_latest_revision" {
  description = "Latest revision name of the Cloud Run service"
  value       = google_cloud_run_service.ext_proc.status[0].latest_ready_revision_name
}

# ==============================================================================
# BACKEND SERVICE OUTPUTS
# ==============================================================================

output "backend_service_id" {
  description = "ID of the regional backend service (for use in LB route/traffic extensions)"
  value       = var.create_backend_service ? google_compute_region_backend_service.ext_proc[0].id : null
}

output "backend_service_self_link" {
  description = "Self-link of the regional backend service"
  value       = var.create_backend_service ? google_compute_region_backend_service.ext_proc[0].self_link : null
}

output "backend_service_name" {
  description = "Name of the regional backend service"
  value       = var.create_backend_service ? google_compute_region_backend_service.ext_proc[0].name : null
}

# ==============================================================================
# NETWORK ENDPOINT GROUP OUTPUTS
# ==============================================================================

output "neg_id" {
  description = "ID of the serverless NEG"
  value       = var.create_backend_service ? google_compute_region_network_endpoint_group.ext_proc[0].id : null
}

output "neg_self_link" {
  description = "Self-link of the serverless NEG"
  value       = var.create_backend_service ? google_compute_region_network_endpoint_group.ext_proc[0].self_link : null
}

# ==============================================================================
# EXTENSION CONFIGURATION OUTPUTS
# ==============================================================================

output "extension_config" {
  description = "Configuration object for LB route/traffic extension (use with google_network_services_lb_*_extension)"
  value = {
    service      = var.create_backend_service ? google_compute_region_backend_service.ext_proc[0].self_link : null
    timeout      = "${var.cloud_run.timeout_seconds}s"
    service_name = google_cloud_run_service.ext_proc.name
    authority    = google_cloud_run_service.ext_proc.status[0].url
  }
}
