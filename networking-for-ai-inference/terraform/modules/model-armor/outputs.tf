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

output "template_id" {
  description = "ID of the Model Armor template"
  value       = var.enable_model_armor ? google_model_armor_template.template[0].template_id : null
}

output "template_name" {
  description = "Full resource name of the Model Armor template"
  value       = var.enable_model_armor ? google_model_armor_template.template[0].name : null
}

output "template_location" {
  description = "Location of the Model Armor template"
  value       = var.enable_model_armor ? google_model_armor_template.template[0].location : null
}

output "service_account_email" {
  description = "Email of the Service Extensions service account (gcp-sa-dep) used for Model Armor"
  value       = local.service_extensions_sa_email
}

output "rai_filters" {
  description = "Configured RAI filters"
  value       = var.rai_filters
}

output "filter_configuration" {
  description = "Summary of filter configuration"
  value = var.enable_model_armor ? {
    rai_filters = {
      count   = length(var.rai_filters)
      filters = var.rai_filters
    }
    sdp_settings = {
      enforcement = var.sdp_basic_filter_enforcement
      pii_types   = var.pii_types
    }
    pi_jailbreak = {
      enforcement      = var.pi_jailbreak_enforcement
      confidence_level = var.pi_jailbreak_confidence_level
    }
    malicious_uri = {
      enforcement = var.malicious_uri_enforcement
    }
  } : null
}

output "error_configuration" {
  description = "Custom error codes and messages"
  value = var.enable_model_armor ? {
    llm_response = {
      code    = var.llm_response_error_code
      message = var.llm_response_error_message
    }
    prompt = {
      code    = var.prompt_error_code
      message = var.prompt_error_message
    }
  } : null
}

output "logging_configuration" {
  description = "Logging and operation settings"
  value = var.enable_model_armor ? {
    log_template_operations = var.log_template_operations
    log_sanitize_operations = var.log_sanitize_operations
    ignore_partial_failures = var.ignore_partial_failures
  } : null
}

output "iam_roles_granted" {
  description = "List of IAM roles granted to Service Extensions service account (gcp-sa-dep) for Model Armor"
  value = var.enable_model_armor && var.enable_iam_bindings ? [
    "roles/container.admin",
    "roles/modelarmor.calloutUser",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/modelarmor.user"
  ] : []
}
