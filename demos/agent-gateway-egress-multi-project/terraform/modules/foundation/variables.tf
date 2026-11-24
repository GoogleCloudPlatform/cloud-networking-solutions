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



variable "governance_project_id" {
  description = "The GCP project ID for the Governance (Service) project"
  type        = string
}

variable "networking_project_id" {
  description = "The GCP project ID for the Networking (Host) project"
  type        = string
}

variable "runtime_project_id" {
  description = "The GCP project ID for the Runtime (Service) project hosting the Agent Runtime"
  type        = string
}

variable "enable_psc_interface" {
  description = "Enable IAM grants for PSC Interface (compute.networkAdmin, dns.peer for Vertex AI service agent)"
  type        = bool
  default     = false
}

variable "manage_shared_vpc" {
  description = "Whether Terraform should manage Shared VPC host enablement and service project attachment. Set to false if Shared VPC is pre-configured by an Organization/Folder Admin."
  type        = bool
  default     = true
}

variable "logging_data_access" {
  description = "Data access audit log configuration. Map of service name to a map of log type (ADMIN_READ|DATA_READ|DATA_WRITE) to optional exempted_members. Use the special 'allServices' key to apply project-wide across every API."
  type = map(object({
    ADMIN_READ = optional(object({ exempted_members = optional(list(string), []) }))
    DATA_READ  = optional(object({ exempted_members = optional(list(string), []) }))
    DATA_WRITE = optional(object({ exempted_members = optional(list(string), []) }))
  }))
  default = {
    "allServices" = {
      ADMIN_READ = {}
      DATA_READ  = {}
      DATA_WRITE = {}
    }
  }
  nullable = false
}
