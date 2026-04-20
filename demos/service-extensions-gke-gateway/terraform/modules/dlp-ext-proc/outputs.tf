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

# ext_proc Service Outputs

output "service_account_email" {
  description = "Email of the service account used by Cloud Run"
  value       = google_service_account.ext_proc.email
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.ext_proc.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.ext_proc.uri
}

output "cloud_run_service_id" {
  description = "ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.ext_proc.id
}

output "backend_service_name" {
  description = "Name of the ext_proc backend service"
  value       = google_compute_backend_service.ext_proc.name
}

output "backend_service_id" {
  description = "ID of the ext_proc backend service"
  value       = google_compute_backend_service.ext_proc.id
}

output "neg_name" {
  description = "Name of the serverless NEG"
  value       = google_compute_region_network_endpoint_group.ext_proc_neg.name
}

output "neg_id" {
  description = "ID of the serverless NEG"
  value       = google_compute_region_network_endpoint_group.ext_proc_neg.id
}

# Traffic Extension Outputs

output "traffic_extension_name" {
  description = "Name of the traffic extension"
  value       = google_network_services_lb_traffic_extension.dlp_ext_proc.name
}

output "traffic_extension_id" {
  description = "ID of the traffic extension"
  value       = google_network_services_lb_traffic_extension.dlp_ext_proc.id
}
