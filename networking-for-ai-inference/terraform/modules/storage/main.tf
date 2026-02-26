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

# GCS Bucket for model storage
module "model_storage_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v53.0.0"
  project_id    = var.project_id
  name          = "${var.project_id}-model-storage"
  location      = var.region
  force_destroy = var.bucket_force_destroy

  # Bucket configuration
  storage_class = var.bucket_storage_class
  versioning    = var.bucket_versioning

  # Lifecycle rules
  lifecycle_rules = {
    delete-old-versions = {
      action = {
        type = "Delete"
      }
      condition = {
        age                = var.bucket_lifecycle_age
        with_state         = "ARCHIVED"
        num_newer_versions = var.bucket_lifecycle_num_versions
      }
    }
  }

  # Labels
  labels = merge(
    var.labels,
    {
      purpose     = "model-storage"
      environment = "production"
      managed-by  = "terraform"
    }
  )
}

# IAM - Allow default compute service account to access the bucket
# GKE Workload Identity access is managed externally in main.tf to avoid dependency cycles
resource "google_storage_bucket_iam_member" "compute_viewer" {
  bucket = module.model_storage_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "compute_creator" {
  bucket = module.model_storage_bucket.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}
