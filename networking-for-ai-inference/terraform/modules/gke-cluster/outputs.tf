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

output "name" {
  description = "GKE cluster name"
  value       = module.gke.name
}

output "id" {
  description = "GKE cluster ID"
  value       = module.gke.id
}

output "endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.gke.ca_certificate
  sensitive   = true
}

output "location" {
  description = "GKE cluster location"
  value       = module.gke.location
}

output "workload_identity_pool" {
  description = "Workload Identity pool"
  value       = "${var.project_id}.svc.id.goog"
}
