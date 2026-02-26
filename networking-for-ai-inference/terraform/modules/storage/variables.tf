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
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number (for service account email construction)"
  type        = string
}

variable "region" {
  description = "GCP region for storage resources"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# GCS Bucket Variables
variable "bucket_force_destroy" {
  description = "Allow deletion of bucket with objects"
  type        = bool
  default     = true
}

variable "bucket_storage_class" {
  description = "Storage class for the bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE"
  }
}

variable "bucket_versioning" {
  description = "Enable versioning for the bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age" {
  description = "Age in days before deleting old versions"
  type        = number
  default     = 90
}

variable "bucket_lifecycle_num_versions" {
  description = "Number of newer versions to keep"
  type        = number
  default     = 3
}
