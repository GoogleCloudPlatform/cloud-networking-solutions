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
 * Root Terraform Configuration
 *
 * Orchestrates deployment of modular infrastructure for MCP gateway services:
 * 1. Foundation: API enablement and quotas
 * 2. Networking: VPC, NAT, static IPs, private DNS zones
 * 3. MCP Cloud Run services + per-service runtime SAs
 * 4. MCP internal Application LB with URL-mask Serverless NEG
 * 5. Public DNS zone and certs (optional)
 */

# Provider configuration lives in providers.tf.

# Phase 1: Foundation - API Enablement and Quotas
module "foundation" {
  source = "./modules/foundation"

  providers = {
    google-beta = google-beta
  }

  project_id           = var.project_id
  enable_psc_interface = var.enable_psc_interface
  logging_data_access  = var.logging_data_access
}

# Phase 1.5: Observability - Log Analytics on _Default + authorization
# debugging dashboard.
module "observability" {
  source = "./modules/observability"

  project_id = var.project_id

  depends_on = [module.foundation]
}

# Phase 2: Networking - VPC, Subnets, NAT, Static IPs
module "networking" {
  source = "./modules/networking"

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  vpc_name    = var.vpc_name
  subnet_name = var.subnet_name

  # Customizable CIDR ranges
  primary_subnet_cidr = var.primary_subnet_cidr
  proxy_subnet_cidr   = var.proxy_subnet_cidr
  psc_subnet_cidr     = var.psc_subnet_cidr

  # PSC Interface (network attachment, firewall).
  enable_psc_interface      = var.enable_psc_interface
  psc_interface_subnet_cidr = var.psc_interface_subnet_cidr

  # Private DNS zone for `run.app.` that resolves every Cloud Run URL to the
  # PSC for Google APIs VIP, so Cloud Run services with internal-only ingress
  # are reachable from the gateway without opening them to the public internet.
  enable_run_app_psc  = var.enable_run_app_psc
  run_app_psc_regions = var.run_app_psc_regions

  # Agent Gateway dedicated subnet (hosts both the new PSC-I network attachment
  # and the relocated MCP internal LB VIP when enable_agent_gateway = true).
  enable_agent_gateway      = var.enable_agent_gateway
  agent_gateway_subnet_cidr = var.agent_gateway_subnet_cidr

  depends_on = [module.foundation]
}

# Artifact Registry — Regional Docker repository for container images
resource "google_artifact_registry_repository" "registry" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.name_prefix}-docker"
  format        = "DOCKER"
  description   = "Regional Docker repository for container images"

  depends_on = [module.foundation]
}

# Cloud Build — Source bucket for regional Cloud Build submissions
resource "google_storage_bucket" "cloudbuild" {
  project                     = var.project_id
  name                        = coalesce(var.cloudbuild_bucket_name, "${var.project_id}_cloudbuild")
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [module.foundation]
}

# Grant Compute Engine default SA full bucket access for Cloud Build source
# uploads. roles/storage.admin (scoped to the bucket) is required because
# Cloud Build's build-creation step calls storage.buckets.get to validate the
# source bucket — a permission not included in roles/storage.objectAdmin.
resource "google_storage_bucket_iam_member" "cloudbuild_compute_sa" {
  bucket = google_storage_bucket.cloudbuild.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${module.foundation.project_number}-compute@developer.gserviceaccount.com"
}

# Grant Compute Engine default SA artifact registry access for Cloud Build
resource "google_project_iam_member" "cloudbuild_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${module.foundation.project_number}-compute@developer.gserviceaccount.com"
}

# Grant Cloud Build service agent storage access for source tarballs
resource "google_storage_bucket_iam_member" "cloudbuild_service_agent" {
  bucket = google_storage_bucket.cloudbuild.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:service-${module.foundation.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

module "model_armor" {
  count  = var.enable_model_armor ? 1 : 0
  source = "./modules/model-armor"

  project_id = var.project_id
  region     = var.region

  enable_model_armor   = var.enable_model_armor
  request_template_id  = var.model_armor_request_template_id
  response_template_id = var.model_armor_response_template_id

  # Admin IAM
  platform_admin_members = var.platform_admin_members

  # RAI filters
  rai_filters = var.model_armor_rai_filters

  # Sensitive Data Protection
  sdp_enforcement = var.model_armor_sdp_enforcement
  pii_types       = var.model_armor_pii_types

  # Prompt Injection & Jailbreak
  pi_jailbreak_enforcement      = var.model_armor_pi_jailbreak_enforcement
  pi_jailbreak_confidence_level = var.model_armor_pi_jailbreak_confidence

  # Malicious URI
  malicious_uri_enforcement = var.model_armor_malicious_uri_enforcement

  # MCP Floor Setting
  enable_mcp_floor_setting = var.enable_model_armor_mcp_floor_setting

  # Vertex AI Integration
  enable_vertex_ai_integration   = var.enable_model_armor_vertex_ai
  vertex_ai_inspect_only         = var.model_armor_vertex_ai_inspect_only
  vertex_ai_enable_cloud_logging = var.model_armor_vertex_ai_cloud_logging

  # Gemini Enterprise Template
  enable_gemini_enterprise_template   = var.enable_model_armor_gemini_enterprise
  gemini_enterprise_template_id       = var.model_armor_gemini_enterprise_template_id
  gemini_enterprise_template_location = var.model_armor_gemini_enterprise_location

  depends_on = [module.foundation]
}


# Phase 10: Agent Engine — Agent Identity IAM bindings
module "agent_engine" {
  count  = var.enable_agent_engine ? 1 : 0
  source = "./modules/agent-engine"

  project_id     = var.project_id
  project_number = module.foundation.project_number

  organization_id        = var.organization_id
  platform_admin_members = var.platform_admin_members

  depends_on = [module.foundation]
}

# Phase 12: MCP Cloud Run services + per-service runtime SAs
# `private_networking = false` (the default) leaves Cloud Run with
# `INGRESS_TRAFFIC_ALL` so callers can hit the *.run.app URL directly. Set the
# master flag to true to restrict ingress to the internal LB.
module "mcp_services" {
  source = "./modules/mcp-cloud-run"

  project_id              = var.project_id
  region                  = var.region
  services                = var.mcp_services
  mcp_internal_dns_domain = local.mcp_internal_dns_domain_or_null
  # Restricts roles/run.invoker to the agent-mcp-invoker SA. Null when
  # agent_engine is disabled, in which case mcp-cloud-run skips the binding
  # and Cloud Run is unreachable until invoker is granted out-of-band.
  invoker_sa_email = var.enable_agent_engine ? module.agent_engine[0].agent_mcp_invoker_email : null

  depends_on = [module.foundation, google_artifact_registry_repository.registry]
}

# Agent Gateway can't validate the self-signed cert the MCP LB falls back to
# when mcp_internal_dns_zone.domain isn't a real, Certificate-Manager-issuable
# subdomain. Catch the misconfiguration at plan time rather than during the
# first agent → MCP HTTPS call.
#
# Only enforced when the master flag is on — otherwise there's no LB and no
# cert to validate; the agent reaches Cloud Run via the *.run.app URL directly.
check "agent_gateway_mcp_cert_prereqs" {
  assert {
    condition     = !var.enable_agent_gateway || var.enable_certificate_manager
    error_message = "enable_agent_gateway = true requires enable_certificate_manager = true so the MCP internal LB serves a Google-managed cert (Agent Gateway does not currently validate self-signed certs)."
  }
  assert {
    condition = !var.enable_agent_gateway || (
      var.mcp_internal_dns_zone != null &&
      var.dns_zone_domain != null &&
      endswith(
        trimsuffix(var.mcp_internal_dns_zone.domain, "."),
        ".${trimsuffix(var.dns_zone_domain, ".")}"
      )
    )
    error_message = "enable_agent_gateway = true requires mcp_internal_dns_zone.domain to be a subdomain of dns_zone_domain (e.g. dns_zone_domain = \"agw.example.com.\" + mcp_internal_dns_zone.domain = \"mcp.agw.example.com.\") so Certificate Manager can issue the cert."
  }
}

# Phase 13: Agent Gateway — governance plane fronting the MCP services.
# Provisions the gateway in AGENT_TO_ANYWHERE mode with PSC-I egress and IAP
# and Model Armor authz extensions. Per-MCP-server `roles/iap.egressor`
# bindings are issued out-of-band by `scripts/grant_agent_mcp_egress.sh`.
module "agent_gateway" {
  count  = var.enable_agent_gateway ? 1 : 0
  source = "./modules/agent-gateway"

  providers = {
    google      = google
    google-beta = google-beta
  }

  project_id = var.project_id
  region     = var.region

  name                           = var.agent_gateway_name
  network_self_link              = module.networking.network_self_link
  agent_gateway_subnet_self_link = module.networking.agent_gateway_subnet_self_link
  agent_gateway_subnet_cidr      = var.agent_gateway_subnet_cidr

  mcp_lb_target_port = var.mcp_lb_protocol == "HTTPS" ? 443 : 80

  enable_model_armor               = var.enable_model_armor
  model_armor_request_template_id  = var.enable_model_armor ? module.model_armor[0].request_template_id : null
  model_armor_response_template_id = var.enable_model_armor ? module.model_armor[0].response_template_id : null

  # Scope the Model Armor CONTENT_AUTHZ policy to the per-MCP-service Host
  # values: when private networking is on, that's `<svc>.<mcp domain>` (the
  # internal LB hostname). When private networking is off, the agent reaches
  # Cloud Run via *.run.app, so flatten over every URL form Cloud Run exposes
  # for each service (both the hash form `<svc>-<hash>-<region>.a.run.app`
  # AND the project-number form `<svc>-<project-number>.<region>.run.app`) —
  # an agent may legitimately call either, and Model Armor host matching is
  # exact-string. The trailing dot on the private zone domain is stripped so
  # the value matches what HTTP clients actually send in the Host header.
  model_armor_authz_hosts = var.enable_model_armor ? (
    flatten([for svc in keys(var.mcp_services) :
      [for u in module.mcp_services.service_url_list[svc] :
    replace(replace(u, "https://", ""), "/", "")]])
  ) : []

  authz_extension_fail_open = var.agent_gateway_authz_fail_open
  iap_iam_enforcement_mode  = var.agent_gateway_iap_iam_enforcement_mode

  # Auto-merge the MCP private zone with any user-supplied domains (e.g.
  # `run.app.`). Computed in main.tf locals so the user only declares the
  # extras they need.
  dns_peering_config = local.agent_gateway_dns_peering_config_effective

  depends_on = [module.foundation, module.networking, module.mcp_internal_lb]
}

# Discovery Engine Admin — Allow user to manage Gemini Enterprise / Discovery Engine
resource "google_project_iam_member" "discoveryengine_admin" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/discoveryengine.admin"
  member   = each.key
}

# Cloud Run Admin — Allow platform admins to manage Cloud Run services
resource "google_project_iam_member" "run_admin" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/run.admin"
  member   = each.key
}

# Phase 15: Agent Registry Endpoints — governance plane fronting the Google API
# services AND the MCP Cloud Run services. Registers all regional, mTLS, and REP
# variants of the specified Google APIs, plus one entry per MCP Cloud Run service
# (URL = https://<service>.<mcp_internal_dns_zone.domain>).
module "agent_registry_endpoints" {
  count  = var.enable_agent_registry_endpoints ? 1 : 0
  source = "./modules/agent-registry-endpoints"

  project_id = var.project_id
  location   = var.region

  google_apis     = var.agent_registry_google_apis
  custom_services = var.agent_registry_custom_services

  mcp_servers = {
    for name in keys(var.mcp_services) : name => {
      tool_spec_path = lookup(var.mcp_tool_specs, name, null) != null ? abspath("${path.root}/${var.mcp_tool_specs[name]}") : null
    }
  }
  # URL mode `cloud_run` registers
  # the literal *.run.app URL from module.mcp_services.service_urls.
  mcp_url_mode            = "cloud_run"
  mcp_internal_dns_domain = local.mcp_internal_dns_domain_or_null
  mcp_service_urls        = module.mcp_services.service_urls

  depends_on = [module.foundation, module.mcp_services, module.mcp_internal_lb]
}
