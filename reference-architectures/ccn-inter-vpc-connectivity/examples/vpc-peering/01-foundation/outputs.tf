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

# Outputs the project and folder IDs

output "on_prem_project_id" {
  description = "The project ID of the on-prem project."
  value       = module.foundation.on_prem_project_id
}

output "prod_project_ids" {
  description = "A map of production project names to their IDs."
  value       = module.foundation.prod_project_ids
}

output "dev_project_ids" {
  description = "A map of development project names to their IDs."
  value       = module.foundation.dev_project_ids
}

output "base_folder_id" {
  description = "The ID of the base folder."
  value       = module.foundation.base_folder_id
}

output "level2_folder_ids" {
  description = "A map of level 2 folder names to their IDs."
  value       = module.foundation.level2_folder_ids
}

output "prod_level3_folder_ids" {
  description = "A map of production level 3 folder names to their IDs."
  value       = module.foundation.prod_level3_folder_ids
}

output "dev_level3_folder_ids" {
  description = "A map of development level 3 folder names to their IDs."
  value       = module.foundation.dev_level3_folder_ids
}

output "org_policy_reset_command" {
  description = "Run this gcloud command to reset compute.restrictVpnPeerIPs on the base folder when deploying with user credentials."
  value       = module.foundation.org_policy_reset_command
}
