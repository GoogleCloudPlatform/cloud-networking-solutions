# Copyright 2025 Duncan James
# SPDX-License-Identifier: Apache-2.0

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
