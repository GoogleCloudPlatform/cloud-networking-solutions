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


data "google_project" "project" {
  project_id = var.project_id
}

locals {
  # Service Extensions service account format: service-PROJECT_NUMBER@gcp-sa-dep.iam.gserviceaccount.com
  # This account is automatically created when networkservices.googleapis.com is enabled
  # See: https://cloud.google.com/service-extensions/docs/configure-extensions-to-google-services
  service_extensions_sa_email = "service-${data.google_project.project.number}@gcp-sa-dep.iam.gserviceaccount.com"
}

resource "google_model_armor_template" "template" {
  count       = var.enable_model_armor ? 1 : 0
  project     = var.project_id
  location    = var.region
  template_id = var.template_id

  # Filter Configuration
  filter_config {
    # RAI Settings Filters
    rai_settings {
      dynamic "rai_filters" {
        for_each = var.rai_filters
        content {
          filter_type      = rai_filters.value.filter_type
          confidence_level = rai_filters.value.confidence_level
        }
      }
    }

    # Sensitive Data Protection Settings
    sdp_settings {
      basic_config {
        filter_enforcement = var.sdp_basic_filter_enforcement
      }
    }

    # PI and Jailbreak Filter Settings
    pi_and_jailbreak_filter_settings {
      filter_enforcement = var.pi_jailbreak_enforcement
      confidence_level   = var.pi_jailbreak_confidence_level
    }

    # Malicious URI Filter Settings
    malicious_uri_filter_settings {
      filter_enforcement = var.malicious_uri_enforcement
    }
  }

  # Template Metadata
  template_metadata {
    custom_llm_response_safety_error_code    = var.llm_response_error_code
    custom_llm_response_safety_error_message = var.llm_response_error_message
    custom_prompt_safety_error_code          = var.prompt_error_code
    custom_prompt_safety_error_message       = var.prompt_error_message
    ignore_partial_invocation_failures       = var.ignore_partial_failures
    log_template_operations                  = var.log_template_operations
    log_sanitize_operations                  = var.log_sanitize_operations
  }
}

# =============================================================================
# IAM Bindings for Service Extensions Service Account (gcp-sa-dep)
# Required for GCPTrafficExtension to call Model Armor from GKE Gateway
# See: https://cloud.google.com/service-extensions/docs/configure-extensions-to-google-services#configure-traffic-ma
# =============================================================================

# Grant container.admin role for GKE access
resource "google_project_iam_member" "service_extensions_container_admin" {
  count   = var.enable_model_armor && var.enable_iam_bindings ? 1 : 0
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${local.service_extensions_sa_email}"
}

# Grant modelarmor.calloutUser role for Model Armor callouts
resource "google_project_iam_member" "service_extensions_callout_user" {
  count   = var.enable_model_armor && var.enable_iam_bindings ? 1 : 0
  project = var.project_id
  role    = "roles/modelarmor.calloutUser"
  member  = "serviceAccount:${local.service_extensions_sa_email}"
}

# Grant serviceusage.serviceUsageConsumer role for API usage
resource "google_project_iam_member" "service_extensions_service_usage" {
  count   = var.enable_model_armor && var.enable_iam_bindings ? 1 : 0
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${local.service_extensions_sa_email}"
}

# Grant modelarmor.user role for Model Armor usage
resource "google_project_iam_member" "service_extensions_model_armor_user" {
  count   = var.enable_model_armor && var.enable_iam_bindings ? 1 : 0
  project = var.project_id
  role    = "roles/modelarmor.user"
  member  = "serviceAccount:${local.service_extensions_sa_email}"
}
