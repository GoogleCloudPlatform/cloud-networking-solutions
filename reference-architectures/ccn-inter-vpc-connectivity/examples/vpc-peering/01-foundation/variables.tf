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

# Defining variables for the organization ID and billing account ID
variable "organization_id" {
  description = "The organization ID."
  type        = string
}

variable "billing_account_id" {
  description = "The ID of the billing account to associate projects with."
  type        = string
}

variable "prefix" {
  description = "Prefix for folders and projects."
  type        = string
  default     = "peer"

  validation {
    condition     = can(regex("^[a-z0-9]{1,7}$", var.prefix))
    error_message = "prefix must be 1 to 7 lowercase alphanumeric characters so generated project IDs stay within the 30-character GCP limit."
  }
}
