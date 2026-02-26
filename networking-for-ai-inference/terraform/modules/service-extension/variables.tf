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
# REQUIRED VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
}

variable "service_name" {
  description = "Name identifier for this service extension (e.g., 'bbr', 'model-extractor')"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.service_name))
    error_message = "service_name must be lowercase alphanumeric with hyphens, 2-63 characters"
  }
}

# ==============================================================================
# NAMING AND LABELING
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "ext"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# SERVICE ACCOUNT CONFIGURATION
# ==============================================================================

variable "create_service_account" {
  description = "Create a new service account for the ext_proc service"
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "Existing service account email to use (required if create_service_account = false)"
  type        = string
  default     = null
}

# ==============================================================================
# CLOUD RUN CONFIGURATION
# ==============================================================================

variable "cloud_run" {
  description = <<-EOT
    Cloud Run service configuration for the ext_proc gRPC service.

    Attributes:
    - image: Container image for the ext_proc service (required)
    - command: Optional command to override container entrypoint
    - port: Container port for gRPC (default: 8080)
    - cpu_limit: CPU limit (default: 1000m)
    - memory_limit: Memory limit (default: 512Mi)
    - min_instances: Minimum instances for autoscaling (default: 1)
    - max_instances: Maximum instances for autoscaling (default: 10)
    - concurrency: Container concurrency (default: 100)
    - timeout_seconds: Request timeout in seconds (default: 30)
    - log_level: Log level for the service (default: INFO)
    - environment_variables: Additional environment variables
  EOT
  type = object({
    image                 = string
    command               = optional(list(string))
    port                  = optional(number, 8080)
    cpu_limit             = optional(string, "1000m")
    memory_limit          = optional(string, "512Mi")
    min_instances         = optional(number, 1)
    max_instances         = optional(number, 10)
    concurrency           = optional(number, 100)
    timeout_seconds       = optional(number, 30)
    log_level             = optional(string, "INFO")
    environment_variables = optional(map(string), {})
  })

  validation {
    condition     = var.cloud_run.min_instances >= 0
    error_message = "cloud_run.min_instances must be >= 0"
  }

  validation {
    condition     = var.cloud_run.max_instances >= var.cloud_run.min_instances
    error_message = "cloud_run.max_instances must be >= min_instances"
  }

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.cloud_run.log_level)
    error_message = "cloud_run.log_level must be one of: DEBUG, INFO, WARNING, ERROR"
  }
}

# ==============================================================================
# IAM CONFIGURATION
# ==============================================================================

variable "grant_iap_invoker" {
  description = "Grant Cloud Run invoker role to IAP service agent"
  type        = bool
  default     = true
}

variable "grant_compute_invoker" {
  description = "Grant Cloud Run invoker role to Compute Engine default service account"
  type        = bool
  default     = true
}

# ==============================================================================
# BACKEND SERVICE CONFIGURATION
# ==============================================================================

variable "create_backend_service" {
  description = "Create a regional backend service and serverless NEG for LB integration"
  type        = bool
  default     = true
}

variable "backend_service" {
  description = <<-EOT
    Backend service configuration for LB ext_proc callouts.

    Attributes:
    - load_balancing_scheme: LB scheme (EXTERNAL_MANAGED, INTERNAL_MANAGED, etc.)
    - timeout_sec: Backend timeout in seconds (default: 30)
    - enable_logging: Enable backend logging (default: true)
    - log_sample_rate: Log sampling rate 0.0-1.0 (default: 1.0)
  EOT
  type = object({
    load_balancing_scheme = optional(string, "EXTERNAL_MANAGED")
    timeout_sec           = optional(number, 30)
    enable_logging        = optional(bool, true)
    log_sample_rate       = optional(number, 1.0)
  })
  default = {}

  validation {
    condition = contains(
      ["EXTERNAL_MANAGED", "INTERNAL_MANAGED", "INTERNAL_SELF_MANAGED"],
      var.backend_service.load_balancing_scheme
    )
    error_message = "backend_service.load_balancing_scheme must be one of: EXTERNAL_MANAGED, INTERNAL_MANAGED, INTERNAL_SELF_MANAGED"
  }

  validation {
    condition     = var.backend_service.log_sample_rate >= 0 && var.backend_service.log_sample_rate <= 1
    error_message = "backend_service.log_sample_rate must be between 0.0 and 1.0"
  }
}
