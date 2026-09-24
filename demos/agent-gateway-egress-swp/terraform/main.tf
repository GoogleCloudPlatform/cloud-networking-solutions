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
 * CUJ2: Agent Gateway Public Egress via Secure Web Proxy + Cloud NAT Static IP
 *
 * Module graph:
 *   foundation → networking → secure-web-proxy
 *                           → mcp-cloud-run (images built in images.tf)
 *                           → agent-gateway → agent-engine
 *
 * All Agent Runtime egress travels:
 *   Reasoning Engine → Agent Gateway (PSC-I) → customer VPC
 *   → Policy-Based Route → Secure Web Proxy (NEXT_HOP_ROUTING_MODE)
 *   → Cloud Router → Cloud NAT (static IP) → public internet
 *   → bug-tickets-mcp Cloud Run (INGRESS_TRAFFIC_ALL, no auth)
 */

locals {
  agent_artifacts_manifest_path = coalesce(
    var.agent_artifacts_manifest_path,
    "${path.module}/../build/agent_artifacts.json",
  )
}

# Phase 1: Foundation — API enablement
module "foundation" {
  source = "./modules/foundation"

  providers = {
    google-beta = google-beta
  }

  project_id           = var.project_id
  enable_psc_interface = true
  logging_data_access  = var.logging_data_access
}

# Phase 2: Networking — VPC, Agent Gateway subnet, Cloud Router, Cloud NAT (static IP)
module "networking" {
  source = "./modules/networking"

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  vpc_name    = var.vpc_name
  subnet_name = var.subnet_name

  primary_subnet_cidr       = var.primary_subnet_cidr
  enable_agent_gateway      = true
  agent_gateway_subnet_cidr = var.agent_gateway_subnet_cidr

  depends_on = [module.foundation]
}

# Phase 3: Secure Web Proxy — next-hop mode with policy-based routes
module "secure_web_proxy" {
  source = "./modules/secure-web-proxy"

  providers = {
    google-beta = google-beta
  }

  project_id        = var.project_id
  region            = var.region
  name_prefix       = var.name_prefix
  network_self_link = module.networking.network_self_link

  # The SWP gateway allocates its internal next-hop IP from the primary (PRIVATE)
  # subnet. The REGIONAL_MANAGED_PROXY subnet is a separate regional prerequisite
  # managed inside the secure-web-proxy module itself.
  private_subnet_id = module.networking.subnet_id

  swp_proxy_subnet_cidr     = var.swp_proxy_subnet_cidr
  agent_gateway_subnet_cidr = var.agent_gateway_subnet_cidr

  depends_on = [module.networking]
}

# Artifact Registry — regional Docker repository for the MCP container image
resource "google_artifact_registry_repository" "registry" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.name_prefix}-docker"
  format        = "DOCKER"
  description   = "Docker repository for bug-tickets-mcp container image"

  depends_on = [module.foundation]
}

# Cloud Build — source bucket for container image builds
resource "google_storage_bucket" "cloudbuild" {
  project                     = var.project_id
  name                        = coalesce(var.cloudbuild_bucket_name, "${var.project_id}-${var.name_prefix}-cloudbuild")
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.cloudbuild_bucket_force_destroy

  lifecycle_rule {
    condition { age = 30 }
    action { type = "Delete" }
  }

  depends_on = [module.foundation]
}

resource "google_storage_bucket_iam_member" "cloudbuild_compute_sa" {
  bucket = google_storage_bucket.cloudbuild.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${module.foundation.project_number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${module.foundation.project_number}-compute@developer.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "cloudbuild_service_agent" {
  bucket = google_storage_bucket.cloudbuild.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:service-${module.foundation.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Grant Cloud Build Editor & Service Usage Consumer to platform admin members so local-exec builds submit cleanly
resource "google_project_iam_member" "platform_admin_cloudbuild" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/cloudbuild.builds.editor"
  member   = each.value
}

resource "google_project_iam_member" "platform_admin_serviceusage" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/serviceusage.serviceUsageConsumer"
  member   = each.value
}

resource "google_project_iam_member" "platform_admin_networkservices_viewer" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/networkservices.viewer"
  member   = each.value
}

resource "time_sleep" "cloudbuild_iam_propagation" {
  create_duration = "30s"

  triggers = {
    compute_sa_bucket    = google_storage_bucket_iam_member.cloudbuild_compute_sa.id
    compute_sa_registry  = google_project_iam_member.cloudbuild_registry.id
    service_agent_bucket = google_storage_bucket_iam_member.cloudbuild_service_agent.id
  }

  depends_on = [
    google_project_iam_member.platform_admin_cloudbuild,
    google_project_iam_member.platform_admin_serviceusage,
  ]
}

# Phase 4: MCP Cloud Run — public, no-auth bug-tickets-mcp service
# private_networking = false → INGRESS_TRAFFIC_ALL; invoker_sa_email = null → no IAM gate
module "mcp_services" {
  source = "./modules/mcp-cloud-run"

  project_id = var.project_id
  region     = var.region

  services = {
    for k, v in var.mcp_services : k => {
      image              = local.mcp_image_uri[k]
      container_port     = v.container_port
      otel_service_name  = v.otel_service_name
      min_instance_count = v.min_instance_count
      max_instance_count = v.max_instance_count
      cpu                = v.cpu
      memory             = v.memory
      env                = v.env
    }
  }

  private_networking = false
  invoker_sa_email   = null

  depends_on = [
    module.foundation,
    google_artifact_registry_repository.registry,
    terraform_data.mcp_image,
  ]
}

# Phase 5: Agent Gateway — AGENT_TO_ANYWHERE, PSC-I into the customer VPC
module "agent_gateway" {
  source = "./modules/agent-gateway"

  providers = {
    google      = google
    google-beta = google-beta
  }

  project_id     = var.project_id
  project_number = module.foundation.project_number
  region         = var.region

  name                           = var.agent_gateway_name
  template_name                  = "${var.name_prefix}-template"
  network_self_link              = module.networking.network_self_link
  agent_gateway_subnet_self_link = module.networking.agent_gateway_subnet_self_link
  agent_gateway_subnet_cidr      = var.agent_gateway_subnet_cidr

  depends_on = [module.foundation, module.networking, module.secure_web_proxy]
}

# Phase 7: Agent Registry Endpoints — registers Google API endpoints and MCP server,
# allowing the Agent Gateway to dynamically build its routing table, and grants
# roles/iap.egressor to the agent principalSet.
module "agent_registry_endpoints" {
  source = "../../agent-gateway/terraform/modules/agent-registry-endpoints"

  project_id = var.project_id
  location   = var.region

  google_api_endpoints = [
    "https://agentregistry.googleapis.com",
    "https://aiplatform.mtls.googleapis.com",
    "https://aiplatform.googleapis.com",
    "https://cloudresourcemanager.mtls.googleapis.com",
    "https://cloudresourcemanager.googleapis.com",
    "https://iamcredentials.mtls.googleapis.com",
    "https://iamcredentials.googleapis.com",
    "https://telemetry.mtls.googleapis.com",
    "https://telemetry.googleapis.com",
    "https://oauth2.googleapis.com",
    "https://{region}-aiplatform.mtls.googleapis.com",
    "https://{region}-aiplatform.googleapis.com",
    "https://aiplatform.{region}.rep.googleapis.com",
    "https://logging.googleapis.com",
    "https://monitoring.googleapis.com",
  ]

  custom_services = [
    {
      id           = "bug-tickets-mcp"
      display_name = "Bug Tickets MCP"
      url          = "${module.mcp_services.service_urls["bug-tickets-mcp"]}/mcp"
    }
  ]

  mcp_servers             = {}
  mcp_url_mode            = "cloud_run"
  mcp_internal_dns_domain = null
  mcp_service_urls        = {}

  iap_egressor_members = ["principalSet://agents.global.org-${var.organization_id}.system.id.goog/attribute.platformContainer/aiplatform/projects/${module.foundation.project_number}"]
  mcp_egressor_members = []

  depends_on = [module.foundation]
}

# Phase 6: Agent Engine — Agent Identity IAM + optional Reasoning Engine deploy
module "agent_engine" {
  source = "./modules/agent-engine"

  project_id     = var.project_id
  project_number = module.foundation.project_number
  region         = var.region

  organization_id        = var.organization_id
  platform_admin_members = var.platform_admin_members

  deploy_reasoning_engine       = var.deploy_reasoning_engine
  agent_gateway_id              = module.agent_gateway.agent_gateway_id
  agent_artifacts_manifest_path = local.agent_artifacts_manifest_path
  agent_staging_bucket          = var.agent_staging_bucket
  agent_model                   = var.agent_model
  model_endpoint_location       = var.model_endpoint_location
  agent_display_name            = var.agent_display_name

  # Pass the MCP server URL so the agent container receives BUG_TICKETS_MCP_URL
  mcp_server_url = try("${module.mcp_services.service_urls["bug-tickets-mcp"]}/mcp", null)

  # Wait for the gateway and registry endpoints to be fully ready before booting the engine.
  engine_depends_on = [
    module.agent_gateway.wait_for_gateway_id,
    module.agent_registry_endpoints.endpoint_egressor_binding_ids
  ]

  depends_on = [module.foundation, module.agent_gateway, module.agent_registry_endpoints]
}
