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
 * Foundation Module for Shared VPC Architecture
 *
 * Sets up the Governance (Service) project and the Networking (Host) project:
 * - Enables required Google Cloud APIs on both projects
 * - Configures the Shared VPC Host Project and Service Project association
 * - Creates necessary Service Agents (networkservices, aiplatform, modelarmor)
 * - Provisions cross-project IAM on the Host project so Governance service agents
 *   can utilize Shared VPC subnets and Private DNS peering
 */

# -----------------------------------------------------------------------------
# 1. Governance Project (Service Project) APIs & Setup
# -----------------------------------------------------------------------------
module "governance_project" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v59.0.0"
  name          = var.governance_project_id
  project_reuse = {}

  services = [
    "compute.googleapis.com",
    "storage.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com",
    "servicenetworking.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "certificatemanager.googleapis.com",
    "sts.googleapis.com",
    "cloudkms.googleapis.com",
    "agentregistry.googleapis.com",
    "modelarmor.googleapis.com",
    "dlp.googleapis.com",
  ]

  logging_data_access = var.logging_data_access
}

# -----------------------------------------------------------------------------
# 2. Networking Project (Host Project) APIs & Setup
# -----------------------------------------------------------------------------
module "networking_project" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v59.0.0"
  name          = var.networking_project_id
  project_reuse = {}

  services = [
    "compute.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "networkconnectivity.googleapis.com",
    "dns.googleapis.com",
    "servicenetworking.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  logging_data_access = var.logging_data_access
}

# -----------------------------------------------------------------------------
# 3. Runtime Project (Service Project) APIs & Setup
# -----------------------------------------------------------------------------
module "runtime_project" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v59.0.0"
  name          = var.runtime_project_id
  project_reuse = {}

  services = [
    "compute.googleapis.com",
    "storage.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "aiplatform.googleapis.com",
    "networkservices.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
  ]

  logging_data_access = var.logging_data_access
}

# -----------------------------------------------------------------------------
# 4. Shared VPC Host Project Enablement & Service Project Attachments
# -----------------------------------------------------------------------------
resource "google_compute_shared_vpc_host_project" "host" {
  project    = module.networking_project.project_id
  depends_on = [module.networking_project]
}

resource "google_compute_shared_vpc_service_project" "service" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = module.governance_project.project_id
  depends_on      = [google_compute_shared_vpc_host_project.host, module.governance_project]
}

resource "google_compute_shared_vpc_service_project" "runtime_service" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = module.runtime_project.project_id
  depends_on      = [google_compute_shared_vpc_host_project.host, module.runtime_project]
}

# -----------------------------------------------------------------------------
# 4. Governance Project Service Identities
# -----------------------------------------------------------------------------

# Ensure Service Extensions service identity exists (for Model Armor and DEP)
resource "google_project_service_identity" "network_services" {
  provider = google-beta
  project  = module.governance_project.project_id
  service  = "networkservices.googleapis.com"

  depends_on = [module.governance_project]
}

# Enable Vertex AI API explicitly in Governance Project
resource "google_project_service" "aiplatform" {
  project            = module.governance_project.project_id
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
  depends_on         = [module.governance_project]
}

# Vertex AI service identity in Governance Project
resource "google_project_service_identity" "aiplatform" {
  provider = google-beta
  project  = module.governance_project.project_id
  service  = "aiplatform.googleapis.com"

  depends_on = [google_project_service.aiplatform]
}

# Model Armor service identity in Governance Project
resource "google_project_service_identity" "model_armor" {
  provider = google-beta
  project  = module.governance_project.project_id
  service  = "modelarmor.googleapis.com"

  depends_on = [module.governance_project]
}

# Allow time for the AI Platform service identity to propagate
resource "time_sleep" "aiplatform_identity_propagation" {
  count           = var.enable_psc_interface ? 1 : 0
  depends_on      = [google_project_service_identity.aiplatform]
  create_duration = "30s"
}

# -----------------------------------------------------------------------------
# 5. Cross-Project IAM on Networking (Host) Project
# The Governance project's service agents need compute.networkUser and dns.peer
# in the Shared VPC Host project to bind to the Shared VPC subnets and DNS.
# -----------------------------------------------------------------------------

# Default Cloud Services SA
resource "google_project_iam_member" "host_cloudservices_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${module.governance_project.number}@cloudservices.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.service]
}

# AI Platform Service Agent
resource "google_project_iam_member" "host_aiplatform_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${google_project_service_identity.aiplatform.email}"
  depends_on = [google_compute_shared_vpc_service_project.service]
}

resource "google_project_iam_member" "host_aiplatform_dns_peer" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/dns.peer"
  member     = "serviceAccount:${google_project_service_identity.aiplatform.email}"
  depends_on = [google_compute_shared_vpc_service_project.service]
}

# Reasoning Engine Service Agent (gcp-sa-aiplatform-re)
resource "google_project_iam_member" "host_aiplatform_re_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${module.governance_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.aiplatform_identity_propagation, google_compute_shared_vpc_service_project.service]
}

resource "google_project_iam_member" "host_aiplatform_re_dns_peer" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/dns.peer"
  member     = "serviceAccount:service-${module.governance_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.aiplatform_identity_propagation, google_compute_shared_vpc_service_project.service]
}

# Agent Gateway Control Plane Service Agent (gcp-sa-agentgateway)
resource "google_project_iam_member" "host_agentgateway_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${module.governance_project.number}@gcp-sa-agentgateway.iam.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.service]
}

resource "google_project_iam_member" "host_agentgateway_dns_peer" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/dns.peer"
  member     = "serviceAccount:service-${module.governance_project.number}@gcp-sa-agentgateway.iam.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.service]
}

# Agent Gateway Egress Proxy Service Agent (DEP - gcp-sa-dep)
resource "google_project_iam_member" "host_agentgateway_dep_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${module.governance_project.number}@gcp-sa-dep.iam.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.service]
}

# -----------------------------------------------------------------------------
# 6. IAM on Governance (Service) Project
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "gov_aiplatform_networkservices_viewer" {
  count   = var.enable_psc_interface ? 1 : 0
  project = module.governance_project.project_id
  role    = "roles/networkservices.viewer"
  member  = "serviceAccount:${google_project_service_identity.aiplatform.email}"
}

resource "google_project_iam_member" "gov_aiplatform_re_networkservices_viewer" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.governance_project.project_id
  role       = "roles/networkservices.viewer"
  member     = "serviceAccount:service-${module.governance_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.aiplatform_identity_propagation]
}

# -----------------------------------------------------------------------------
# 7. Runtime Project Service Identities
# -----------------------------------------------------------------------------
resource "google_project_service_identity" "runtime_aiplatform" {
  provider   = google-beta
  project    = module.runtime_project.project_id
  service    = "aiplatform.googleapis.com"
  depends_on = [module.runtime_project]
}

resource "time_sleep" "runtime_aiplatform_identity_propagation" {
  count           = var.enable_psc_interface ? 1 : 0
  depends_on      = [google_project_service_identity.runtime_aiplatform]
  create_duration = "30s"
}

# -----------------------------------------------------------------------------
# 8. Cross-Project IAM on Networking (Host) Project for Runtime Project
# Allows Runtime project workloads to resolve DNS and interact with Shared VPC
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "host_runtime_cloudservices_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${module.runtime_project.number}@cloudservices.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.runtime_service]
}

resource "google_project_iam_member" "host_runtime_aiplatform_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${google_project_service_identity.runtime_aiplatform.email}"
  depends_on = [google_compute_shared_vpc_service_project.runtime_service]
}

resource "google_project_iam_member" "host_runtime_aiplatform_dns_peer" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/dns.peer"
  member     = "serviceAccount:${google_project_service_identity.runtime_aiplatform.email}"
  depends_on = [google_compute_shared_vpc_service_project.runtime_service]
}

resource "google_project_iam_member" "host_runtime_aiplatform_re_network_user" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${module.runtime_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.runtime_aiplatform_identity_propagation, google_compute_shared_vpc_service_project.runtime_service]
}

resource "google_project_iam_member" "host_runtime_aiplatform_re_dns_peer" {
  count      = var.enable_psc_interface ? 1 : 0
  project    = module.networking_project.project_id
  role       = "roles/dns.peer"
  member     = "serviceAccount:service-${module.runtime_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.runtime_aiplatform_identity_propagation, google_compute_shared_vpc_service_project.runtime_service]
}

# -----------------------------------------------------------------------------
# 9. Cross-Project IAM on Governance Project for Runtime Project
# Authorizes Runtime Vertex AI service agents to attach to the Central Agent Gateway
# -----------------------------------------------------------------------------

# Custom role following Google Cloud enterprise least-privilege architecture
# Grants networkservices.agentGateways.get, networkservices.agentGateways.use, and networkservices.operations.get
resource "google_project_iam_custom_role" "agw_cross_project_sa" {
  project     = module.governance_project.project_id
  role_id     = "ar_agw_cross_project_sa"
  title       = "Runtime Agent Gateway Cross-Project SA"
  description = "Authorizes cross-project Spoke Vertex AI Service Agents to discover and bind to Central Agent Gateway"
  permissions = [
    "networkservices.agentGateways.get",
    "networkservices.agentGateways.use",
    "networkservices.operations.get",
  ]
}

resource "google_project_iam_member" "gov_runtime_aiplatform_agw_cross_project" {
  project    = module.governance_project.project_id
  role       = google_project_iam_custom_role.agw_cross_project_sa.name
  member     = "serviceAccount:${google_project_service_identity.runtime_aiplatform.email}"
  depends_on = [google_project_iam_custom_role.agw_cross_project_sa]
}

resource "google_project_iam_member" "gov_runtime_aiplatform_re_agw_cross_project" {
  project    = module.governance_project.project_id
  role       = google_project_iam_custom_role.agw_cross_project_sa.name
  member     = "serviceAccount:service-${module.runtime_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [google_project_iam_custom_role.agw_cross_project_sa, time_sleep.runtime_aiplatform_identity_propagation]
}

resource "google_project_iam_member" "gov_runtime_aiplatform_networkservices_viewer" {
  project = module.governance_project.project_id
  role    = "roles/networkservices.viewer"
  member  = "serviceAccount:${google_project_service_identity.runtime_aiplatform.email}"
}

resource "google_project_iam_member" "gov_runtime_aiplatform_re_networkservices_viewer" {
  project    = module.governance_project.project_id
  role       = "roles/networkservices.viewer"
  member     = "serviceAccount:service-${module.runtime_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.runtime_aiplatform_identity_propagation]
}

resource "google_project_iam_member" "gov_runtime_aiplatform_re_agent_registry_viewer" {
  project    = module.governance_project.project_id
  role       = "roles/agentregistry.viewer"
  member     = "serviceAccount:service-${module.runtime_project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  depends_on = [time_sleep.runtime_aiplatform_identity_propagation]
}
