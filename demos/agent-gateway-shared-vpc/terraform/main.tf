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
 * Agent Gateway with Shared VPC (CUJ2 Extension)
 *
 * Deploys a two-project architecture separating Network Administration from AI & Governance:
 *
 * 1. Networking Project (Host Project):
 *    - Shared VPC Host enablement & Service Project association
 *    - Shared VPC network, primary subnet, Agent Gateway PSC-I subnet
 *    - Private DNS Zones (googleapis.com private resolution)
 *    - Secure Web Proxy (SWP in next-hop mode, proxy subnet, policy-based routes)
 *    - Cloud Router & Cloud NAT with static external IP
 *    - Cross-project IAM granting compute.networkUser and dns.peer to Governance Service Agents
 *
 * 2. Governance Project (Service Project):
 *    - Foundation APIs & Service Agents (networkservices, aiplatform, modelarmor)
 *    - Agent Gateway PSC-I Network Attachment connected to the Shared VPC subnet
 *    - Agent Connectivity Template (AGENT_TO_ANYWHERE, CENTRALIZED)
 *    - Agent Gateway instance & AuthzPolicy (allow-all)
 *    - Agent Registry endpoints (Google APIs & MCP custom service) & IAP egressor IAM
 *    - Model Armor templates (request/response guardrails, PI/jailbreak, RAI, DLP)
 *    - MCP Cloud Run service (bug-tickets-mcp) & Artifact Registry
 *    - Vertex AI Reasoning Engine (Software Bug Triage Agent)
 */

locals {
  agent_artifacts_manifest_path = coalesce(
    var.agent_artifacts_manifest_path,
    "${path.module}/../build/agent_artifacts.json",
  )
}

# -----------------------------------------------------------------------------
# Phase 1: Foundation — APIs, Shared VPC association & cross-project IAM
# -----------------------------------------------------------------------------
module "foundation" {
  source = "./modules/foundation"

  providers = {
    google      = google
    google-beta = google-beta
  }

  governance_project_id = var.governance_project_id
  networking_project_id = var.networking_project_id
  enable_psc_interface  = true
  logging_data_access   = var.logging_data_access
}

# -----------------------------------------------------------------------------
# Phase 2: Networking — Shared VPC, Subnets, Cloud NAT (Host Project)
# -----------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  providers = {
    google      = google.networking
    google-beta = google-beta.networking
  }

  project_id  = var.networking_project_id
  region      = var.region
  name_prefix = var.name_prefix
  vpc_name    = var.vpc_name
  subnet_name = var.subnet_name

  primary_subnet_cidr       = var.primary_subnet_cidr
  enable_agent_gateway      = true
  agent_gateway_subnet_cidr = var.agent_gateway_subnet_cidr

  depends_on = [module.foundation]
}

# -----------------------------------------------------------------------------
# Phase 3: Secure Web Proxy — Next-hop mode & Policy-Based Routes (Host Project)
# -----------------------------------------------------------------------------
module "secure_web_proxy" {
  source = "./modules/secure-web-proxy"

  providers = {
    google      = google.networking
    google-beta = google-beta.networking
  }

  project_id        = var.networking_project_id
  region            = var.region
  name_prefix       = var.name_prefix
  network_self_link = module.networking.network_self_link

  private_subnet_id         = module.networking.subnet_id
  swp_proxy_subnet_cidr     = var.swp_proxy_subnet_cidr
  agent_gateway_subnet_cidr = var.agent_gateway_subnet_cidr

  depends_on = [module.networking]
}

# -----------------------------------------------------------------------------
# Phase 4: Artifact Registry & Cloud Build (Governance Project)
# -----------------------------------------------------------------------------

# Artifact Registry — regional Docker repository for the MCP container image
resource "google_artifact_registry_repository" "registry" {
  project       = var.governance_project_id
  location      = var.region
  repository_id = "${var.name_prefix}-docker"
  format        = "DOCKER"
  description   = "Docker repository for bug-tickets-mcp container image"

  depends_on = [module.foundation]
}

# Cloud Build — source bucket for container image builds
resource "google_storage_bucket" "cloudbuild" {
  project                     = var.governance_project_id
  name                        = coalesce(var.cloudbuild_bucket_name, "${var.governance_project_id}-${var.name_prefix}-cloudbuild")
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
  member = "serviceAccount:${module.foundation.governance_project_number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_registry" {
  project = var.governance_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${module.foundation.governance_project_number}-compute@developer.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "cloudbuild_service_agent" {
  bucket = google_storage_bucket.cloudbuild.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:service-${module.foundation.governance_project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Grant Cloud Build Editor & Service Usage Consumer to platform admin members so local-exec builds submit cleanly
resource "google_project_iam_member" "platform_admin_cloudbuild" {
  for_each = toset(var.platform_admin_members)
  project  = var.governance_project_id
  role     = "roles/cloudbuild.builds.editor"
  member   = each.value
}

resource "google_project_iam_member" "platform_admin_serviceusage" {
  for_each = toset(var.platform_admin_members)
  project  = var.governance_project_id
  role     = "roles/serviceusage.serviceUsageConsumer"
  member   = each.value
}

resource "google_project_iam_member" "platform_admin_networkservices_viewer" {
  for_each = toset(var.platform_admin_members)
  project  = var.governance_project_id
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

# -----------------------------------------------------------------------------
# Phase 5: MCP Cloud Run (Governance Project)
# -----------------------------------------------------------------------------
module "mcp_services" {
  source = "./modules/mcp-cloud-run"

  project_id = var.governance_project_id
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

# -----------------------------------------------------------------------------
# Phase 6: Agent Gateway (Governance Project, PSC-I into Shared VPC)
# -----------------------------------------------------------------------------
module "agent_gateway" {
  source = "./modules/agent-gateway"

  providers = {
    google      = google
    google-beta = google-beta
  }

  project_id     = var.governance_project_id
  project_number = module.foundation.governance_project_number
  region         = var.region

  name                           = var.agent_gateway_name
  network_self_link              = module.networking.network_self_link
  agent_gateway_subnet_self_link = module.networking.agent_gateway_subnet_self_link
  agent_gateway_subnet_cidr      = var.agent_gateway_subnet_cidr

  depends_on = [
    module.foundation,
    module.networking,
    module.secure_web_proxy,
    module.agent_registry_endpoints,
  ]
}

# -----------------------------------------------------------------------------
# Phase 7: Agent Registry Endpoints (Governance Project)
# -----------------------------------------------------------------------------
module "agent_registry_endpoints" {
  source = "../../agent-gateway/terraform/modules/agent-registry-endpoints"

  project_id = var.governance_project_id
  location   = var.region

  custom_services = [
    {
      id           = "bug-tickets-mcp"
      display_name = "Bug Tickets MCP"
      url          = "${module.mcp_services.service_urls["bug-tickets-mcp"]}/mcp"
    }
  ]

  depends_on = [module.foundation]
}

# Grant roles/iap.egressor to Agent Identity in Governance Project
resource "google_project_iam_member" "gov_agent_identity_iap_egressor" {
  project = var.governance_project_id
  role    = "roles/iap.egressor"
  member  = "principalSet://agents.global.org-${var.organization_id}.system.id.goog/attribute.platformContainer/aiplatform/projects/${module.foundation.governance_project_number}"
}

# -----------------------------------------------------------------------------
# Phase 8: Model Armor (Governance Project)
# -----------------------------------------------------------------------------
module "model_armor" {
  source = "./modules/model-armor"

  project_id = var.governance_project_id
  region     = var.region

  enable_model_armor   = var.enable_model_armor
  request_template_id  = var.model_armor_request_template_id
  response_template_id = var.model_armor_response_template_id

  rai_filters = var.model_armor_rai_filters

  sdp_enforcement = var.model_armor_sdp_enforcement
  pii_types       = var.model_armor_pii_types

  pi_jailbreak_enforcement      = var.model_armor_pi_jailbreak_enforcement
  pi_jailbreak_confidence_level = var.model_armor_pi_jailbreak_confidence

  malicious_uri_enforcement = var.model_armor_malicious_uri_enforcement

  platform_admin_members = var.platform_admin_members

  enable_iam_bindings            = true
  enable_mcp_floor_setting       = true
  enable_vertex_ai_integration   = true
  vertex_ai_inspect_only         = false
  vertex_ai_enable_cloud_logging = true

  depends_on = [module.foundation]
}

# -----------------------------------------------------------------------------
# Phase 9: Agent Engine (Governance Project)
# -----------------------------------------------------------------------------
module "agent_engine" {
  source = "./modules/agent-engine"

  project_id     = var.governance_project_id
  project_number = module.foundation.governance_project_number
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
    module.agent_registry_endpoints.service_ids,
  ]

  depends_on = [
    module.foundation,
    module.agent_gateway,
    module.agent_registry_endpoints,
    module.model_armor,
  ]
}
