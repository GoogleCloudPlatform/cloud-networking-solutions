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

output "governance_project_id" {
  description = "The Governance (Service) project ID"
  value       = module.governance_project.project_id
}

output "governance_project_number" {
  description = "The Governance (Service) project number"
  value       = module.governance_project.number
}

output "networking_project_id" {
  description = "The Networking (Host) project ID"
  value       = module.networking_project.project_id
}

output "networking_project_number" {
  description = "The Networking (Host) project number"
  value       = module.networking_project.number
}

output "runtime_project_id" {
  description = "The Runtime (Service) project ID"
  value       = module.runtime_project.project_id
}

output "runtime_project_number" {
  description = "The Runtime (Service) project number"
  value       = module.runtime_project.number
}

output "runtime_aiplatform_sa_email" {
  description = "Runtime Vertex AI service agent email"
  value       = google_project_service_identity.runtime_aiplatform.email
}

output "shared_vpc_ready" {
  description = "Identifier confirming Shared VPC service project association is active"
  value       = google_compute_shared_vpc_service_project.service.id
}

output "model_armor_service_agent_email" {
  description = "Model Armor service agent email"
  value       = google_project_service_identity.model_armor.email
}
