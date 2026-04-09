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


output "proxy_name" {
  description = "Name of the created Apigee API proxy"
  value       = google_apigee_api.extension_proxy.name
}

output "proxy_id" {
  description = "ID of the created Apigee API proxy"
  value       = google_apigee_api.extension_proxy.id
}

output "proxy_revision" {
  description = "Latest revision of the Apigee API proxy"
  value       = google_apigee_api.extension_proxy.revision
}

output "latest_revision_id" {
  description = "Latest revision ID of the Apigee API proxy"
  value       = google_apigee_api.extension_proxy.latest_revision_id
}

output "deployment_id" {
  description = "ID of the Apigee API proxy deployment"
  value       = null_resource.extension_proxy_deployment.id
}

output "deployment_environment" {
  description = "Environment where the proxy is deployed"
  value       = var.apigee_environment
}

output "deployed_revision" {
  description = "Deployed revision of the API proxy"
  value       = google_apigee_api.extension_proxy.latest_revision_id
}

output "base_path" {
  description = "Base path where the proxy is accessible"
  value       = "/${var.proxy_name}"
}

output "bundle_path" {
  description = "Path to the generated proxy bundle ZIP file"
  value       = data.archive_file.extension_proxy_bundle.output_path
}
