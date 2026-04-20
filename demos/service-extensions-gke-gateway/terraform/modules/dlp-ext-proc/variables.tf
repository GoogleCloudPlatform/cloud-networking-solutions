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

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run deployment"
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "dlp-ext-proc"
}

variable "image" {
  description = "Container image URL for the DLP ext_proc service"
  type        = string
}

variable "dlp_info_types" {
  description = "Comma-separated DLP info types to detect (empty string uses application defaults)"
  type        = string
  default     = ""
}

variable "dlp_min_likelihood" {
  description = "Minimum detection likelihood for DLP findings"
  type        = string
  default     = "LIKELY"
}

variable "redact_request" {
  description = "Redact PII in request bodies"
  type        = bool
  default     = false
}

variable "redact_response" {
  description = "Redact PII in response bodies"
  type        = bool
  default     = true
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances (for warm standby)"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 100
}

variable "cpu" {
  description = "CPU allocation for Cloud Run (1000m = 1 vCPU)"
  type        = string
  default     = "1000m"
}

variable "memory" {
  description = "Memory allocation for Cloud Run"
  type        = string
  default     = "512Mi"
}

variable "timeout_seconds" {
  description = "Request timeout in seconds"
  type        = number
  default     = 30
}

variable "forwarding_rules" {
  description = "List of forwarding rule IDs for the traffic extension"
  type        = list(string)
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    service    = "dlp-ext-proc"
  }
}
