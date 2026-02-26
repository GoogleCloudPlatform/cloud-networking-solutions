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
  description = "The GCP project ID"
  type        = string
}

variable "enabled_services" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    # Core GCP services
    "compute.googleapis.com",
    "storage.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "dns.googleapis.com",

    # GKE and container services
    "container.googleapis.com",
    "containerregistry.googleapis.com",
    "artifactregistry.googleapis.com",
    "containerfilesystem.googleapis.com",
    "containersecurity.googleapis.com",

    # Cloud Run services
    "run.googleapis.com",

    # Monitoring and logging
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com",

    # Networking & Security
    "servicenetworking.googleapis.com",
    "networkmanagement.googleapis.com",
    "networkservices.googleapis.com",
    "modelarmor.googleapis.com",

    # Security and IAM
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudkms.googleapis.com",
    "binaryauthorization.googleapis.com",
    "secretmanager.googleapis.com",
    "iap.googleapis.com",

    # Other essential services
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "stackdriver.googleapis.com",
    "autoscaling.googleapis.com",
    "cloudbuild.googleapis.com",

    # Certificate Manager
    "certificatemanager.googleapis.com",

    # Quota management
    "cloudquotas.googleapis.com",

    # Apigee services
    "apigee.googleapis.com",

    # Vertex AI services
    "aiplatform.googleapis.com"
  ]
}
