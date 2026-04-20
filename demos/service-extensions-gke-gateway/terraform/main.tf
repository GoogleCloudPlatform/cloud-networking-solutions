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

/**
 * Root Terraform Configuration
 *
 * Orchestrates deployment of modular infrastructure for MCP gateway services:
 * 1. Foundation: API enablement and quotas
 * 2. Networking: VPC, NAT, and static IPs
 * 3. GKE Node Service Account: Dedicated SA for node pools
 * 4. GKE Clusters: Multiple clusters with GPU support
 * 5. DNS: DNS zones and records
 */

data "google_project" "main" {
  project_id = var.project_id
}

# Phase 1: Foundation - API Enablement and Quotas
module "foundation" {
  source = "./modules/foundation"

  providers = {
    google-beta = google-beta
  }

  project_id           = var.project_id
  enable_psc_interface = var.enable_psc_interface
}

# Phase 2: Networking - VPC, Subnets, NAT, and Static IPs
module "networking" {
  source = "./modules/networking"

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  vpc_name    = var.vpc_name
  subnet_name = var.subnet_name

  # Customizable CIDR ranges
  primary_subnet_cidr = var.primary_subnet_cidr
  pods_cidr           = var.pods_cidr
  services_cidr       = var.services_cidr
  proxy_subnet_cidr   = var.proxy_subnet_cidr
  psc_subnet_cidr     = var.psc_subnet_cidr

  # Secondary range names
  pods_range_name     = var.pods_range_name
  services_range_name = var.services_range_name

  # Gateway scope (regional or null)
  gateway_scope = var.gateway_scope

  # Apigee internal DNS zone (private zone with no VPC attachment)
  apigee_internal_dns_zone = var.enable_apigee ? var.apigee_internal_dns_zone : null

  # PSC Interface (network attachment, firewall, DNS zone)
  enable_psc_interface      = var.enable_psc_interface
  psc_interface_subnet_cidr = var.psc_interface_subnet_cidr
  psc_interface_dns_zone    = var.enable_psc_interface ? var.psc_interface_dns_zone : null

  depends_on = [module.foundation]
}

# Phase 3: GKE Node Service Account - Dedicated SA for node pools
module "gke_node_service_account" {
  source = "./modules/gke-node-service-account"

  project_id     = var.project_id
  project_number = module.foundation.project_number

  service_account_name         = "gke-${var.name_prefix}-nodes"
  service_account_display_name = "GKE Node Service Account (${var.name_prefix})"
  service_account_description  = "Dedicated service account for GKE node pools in ${var.project_id}"

  enable_secret_manager = var.enable_secret_manager

  depends_on = [module.foundation]
}

# Phase 4: GKE Clusters - Multiple clusters with for_each pattern
module "gke_clusters" {
  source   = "./modules/gke-cluster"
  for_each = var.clusters

  project_id           = var.project_id
  name                 = each.key
  region               = var.region
  network_self_link    = module.networking.network_self_link
  subnetwork_self_link = module.networking.subnet_self_link
  node_zones           = module.networking.available_zones

  dns_domain          = each.value.dns_domain
  pods_range_name     = var.pods_range_name
  services_range_name = var.services_range_name

  # Optional cluster-specific configuration
  deletion_protection = each.value.deletion_protection

  # Secret sync configuration for syncing secrets from Secret Manager to the cluster
  secret_sync_config = each.value.secret_sync_config

  # Use dedicated service account for nodes
  node_service_account = module.gke_node_service_account.email

  depends_on = [module.networking, module.gke_node_service_account]
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
  name                        = "${var.project_id}_cloudbuild"
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

# Grant Compute Engine default SA storage access for Cloud Build source uploads
resource "google_storage_bucket_iam_member" "cloudbuild_compute_sa" {
  bucket = google_storage_bucket.cloudbuild.name
  role   = "roles/storage.objectAdmin"
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

# Phase 5: Certificates — Google-managed TLS via Certificate Manager
module "certificates" {
  count  = var.enable_certificate_manager ? 1 : 0
  source = "./modules/certificates"

  project_id                 = var.project_id
  region                     = var.region
  dns_zone_domain            = var.dns_zone_domain
  enable_certificate_manager = var.enable_certificate_manager
  gateway_scope              = var.gateway_scope

  depends_on = [module.foundation]
}

# Phase 6: DNS - DNS Zones and Records
module "dns" {
  count  = var.dns_zone_domain != null ? 1 : 0
  source = "./modules/dns"

  project_id      = var.project_id
  dns_zone_domain = var.dns_zone_domain
  dns_zone_name   = var.dns_zone_name

  enable_certificate_manager = var.enable_certificate_manager
  certificate_dns_authorizations_regional = var.enable_certificate_manager && var.gateway_scope == "regional" ? {
    "primary"  = module.certificates[0].regional_dns_authorizations["${replace(trimsuffix(var.dns_zone_domain, "."), ".", "-")}-regional"]
    "internal" = module.certificates[0].regional_dns_authorizations["internal-auth-regional"]
  } : null

  certificate_dns_authorizations_global = var.enable_certificate_manager ? {
    "primary" = module.certificates[0].global_dns_authorizations["${replace(trimsuffix(var.dns_zone_domain, "."), ".", "-")}-global"]
  } : null

  internal_gateway_ip = module.networking.internal_gateway_ip

  enable_self_managed_gateway_dns  = false
  enable_self_managed_internal_dns = false

  vpc_self_links = [module.networking.network_self_link]

  depends_on = [module.networking, module.certificates]
}

module "model_armor" {
  count  = var.enable_model_armor ? 1 : 0
  source = "./modules/model-armor"

  project_id = var.project_id
  region     = var.region

  enable_model_armor = var.enable_model_armor
  template_id        = var.model_armor_template_id

  # Admin IAM
  model_armor_admin_members = var.model_armor_admin_members

  # RAI filters
  rai_filters = var.model_armor_rai_filters

  # Sensitive Data Protection
  sdp_basic_filter_enforcement = var.model_armor_sdp_enforcement
  pii_types                    = var.model_armor_pii_types

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

# Phase 7: DLP ext_proc — service extension for PII redaction
module "dlp_ext_proc" {
  count  = var.enable_dlp_ext_proc ? 1 : 0
  source = "./modules/dlp-ext-proc"

  project_id = var.project_id
  region     = var.region
  image      = var.dlp_ext_proc_image

  dlp_info_types     = var.dlp_ext_proc_info_types
  dlp_min_likelihood = var.dlp_ext_proc_min_likelihood
  redact_request     = var.dlp_ext_proc_redact_request
  redact_response    = var.dlp_ext_proc_redact_response

  forwarding_rules = var.dlp_ext_proc_forwarding_rules

  labels = {
    managed-by = "terraform"
    component  = "dlp-ext-proc"
  }

  depends_on = [module.foundation]
}

# Phase 10: Agent Engine — Agent Identity IAM bindings
module "agent_engine" {
  count  = var.enable_agent_engine ? 1 : 0
  source = "./modules/agent-engine"

  project_id     = var.project_id
  project_number = module.foundation.project_number

  organization_id = var.organization_id
  demo_users      = var.demo_users

  depends_on = [module.foundation]
}

# Phase 11: Apigee — API Management Platform
module "apigee" {
  count  = var.enable_apigee ? 1 : 0
  source = "./modules/apigee"

  project_id     = var.project_id
  project_number = module.foundation.project_number
  region         = var.region

  organization         = var.apigee_organization
  vpc_id               = var.apigee_vpc_id
  envgroups            = var.apigee_envgroups
  environments         = var.apigee_environments
  instances            = var.apigee_instances
  endpoint_attachments = var.apigee_endpoint_attachments

  create_service_accounts       = var.apigee_create_service_accounts
  service_account_prefix        = var.apigee_service_account_prefix
  create_apim_operator_iam      = var.apigee_create_apim_operator_iam
  enable_apim_workload_identity = var.apigee_enable_apim_workload_identity
  apim_operator_namespace       = var.apigee_apim_operator_namespace
  apim_operator_ksa             = var.apigee_apim_operator_ksa

  # Northbound LB (PSC)
  northbound_lb = var.apigee_enable_northbound_lb ? {
    network_self_link  = module.networking.network_self_link
    subnet_self_link   = module.networking.subnet_self_link
    ssl_certificate_id = module.certificates[0].internal_certificate_id
    instances = {
      for k, v in var.apigee_instances : k => {}
    }
  } : null

  # Southbound DNS peering
  dns_peering_zones = {
    for k, v in var.apigee_dns_peering_zones : k => {
      domain            = v.domain
      description       = v.description
      target_project_id = var.project_id
      target_network_id = module.networking.network_name
    }
  }

  # Southbound wildcard DNS record
  internal_dns_wildcard = var.apigee_internal_dns_zone != null && var.apigee_internal_dns_wildcard_endpoint_attachment != null ? {
    managed_zone        = module.networking.apigee_internal_dns_zone_name
    domain              = var.apigee_internal_dns_zone.domain
    endpoint_attachment = var.apigee_internal_dns_wildcard_endpoint_attachment
  } : null

  depends_on = [module.foundation]
}

# DNS A record for Apigee northbound LB (api.internal.ai-demo.gcp.sc-ccn.xyz → LB IP)
resource "google_dns_record_set" "apigee_northbound" {
  count = var.enable_apigee && var.apigee_enable_northbound_lb && var.dns_zone_domain != null ? 1 : 0

  project      = var.project_id
  name         = "api.${module.dns[0].internal_dns_domain}"
  managed_zone = module.dns[0].internal_dns_zone_name
  type         = "A"
  ttl          = 300
  rrdatas      = [module.apigee[0].northbound_lb_ip]

  depends_on = [module.dns, module.apigee]
}

# Phase 12: GKE Workload Identity — IAM bindings for MCP server KSAs
module "corporate_email_identity" {
  source              = "./modules/gke-workload-identity"
  project_id          = var.project_id
  project_number      = data.google_project.main.number
  k8s_service_account = "corporate-email"
  roles               = ["roles/cloudtrace.agent", "roles/monitoring.metricWriter", "roles/logging.logWriter", "roles/serviceusage.serviceUsageConsumer", "roles/telemetry.writer"]
  depends_on          = [module.foundation, module.gke_clusters]
}

module "legacy_dms_identity" {
  source              = "./modules/gke-workload-identity"
  project_id          = var.project_id
  project_number      = data.google_project.main.number
  k8s_service_account = "legacy-dms"
  roles               = ["roles/cloudtrace.agent", "roles/monitoring.metricWriter", "roles/logging.logWriter", "roles/serviceusage.serviceUsageConsumer", "roles/telemetry.writer"]
  depends_on          = [module.foundation, module.gke_clusters]
}

module "income_verification_api_identity" {
  source              = "./modules/gke-workload-identity"
  project_id          = var.project_id
  project_number      = data.google_project.main.number
  k8s_service_account = "income-verification-api"
  roles               = ["roles/cloudtrace.agent", "roles/monitoring.metricWriter", "roles/logging.logWriter", "roles/serviceusage.serviceUsageConsumer", "roles/telemetry.writer"]
  depends_on          = [module.foundation, module.gke_clusters]
}

module "dlp_ext_proc_identity" {
  source              = "./modules/gke-workload-identity"
  project_id          = var.project_id
  project_number      = data.google_project.main.number
  k8s_service_account = "dlp-ext-proc"
  roles               = ["roles/dlp.user", "roles/cloudtrace.agent", "roles/monitoring.metricWriter", "roles/logging.logWriter", "roles/serviceusage.serviceUsageConsumer", "roles/telemetry.writer"]
  depends_on          = [module.foundation, module.gke_clusters]
}

# Discovery Engine Admin — Allow user to manage Gemini Enterprise / Discovery Engine
resource "google_project_iam_member" "discoveryengine_admin" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/discoveryengine.admin"
  member   = each.key
}
