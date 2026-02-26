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
 * Orchestrates deployment of modular infrastructure for AI/ML inference gateway:
 * 1. Foundation: API enablement and quotas
 * 2. Networking: VPC, NAT, and static IPs
 * 3. GKE Clusters: Multiple clusters with GPU support
 * 4. Semantic Cache: Vertex AI + Apigee integration
 * 5. Storage: GCS buckets, secrets, artifact registry
 * 6. Certificates: SSL/TLS certificates
 * 7. DNS: DNS zones and records
 * 8. Model Armor: Security templates and IAM
 * 9. Cloud Run App: Frontend application
 * 10. IAP Load Balancer: Identity-Aware Proxy and load balancing
 * 11. Self Managed Inference Gateway: Self-managed LB with body-based routing
 */

resource "time_static" "deployed_index_suffix" {}

# Local Variables
locals {
  # Unique ID for deployed index to avoid conflicts
  deployed_index_id = "semantic_cache_deployed_${formatdate("YYYYMMDDHHmm", time_static.deployed_index_suffix.rfc3339)}"
  # Merge gateway hostnames into Apigee environment groups for seamless routing
  # The GKE Service Extension passes the client's Host header to Apigee,
  # so Apigee must recognize these hostnames.
  final_apigee_envgroups = {
    for k, v in var.apigee_envgroups : k => distinct(concat(
      v,
      # Add GKE Gateway hostname to 'prod' group
      k == "prod" && var.gke_gateway != null ? [var.gke_gateway.gateway.hostname] : [],
      # Add internal gateway override if present
      k == "prod" && var.internal_gateway_hostname != null ? [var.internal_gateway_hostname] : [],
      # Add user-provided extra hostnames (e.g. GKE internal authorities)
      k == "prod" ? var.extra_apigee_hostnames : []
    ))
  }

  # Self Managed Gateway subdomain extraction from domain name
  self_managed_gateway_subdomain = var.self_managed_gateway != null ? (
    length(split(".", var.self_managed_gateway.domain.name)) > 0 ? split(".", var.self_managed_gateway.domain.name)[0] : "smg"
  ) : null
}

# Phase 1: Foundation - API Enablement and Quotas
module "foundation" {
  source = "./modules/foundation"

  providers = {
    google-beta = google-beta
  }

  project_id = var.project_id
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

  # Secondary range names
  pods_range_name     = var.pods_range_name
  services_range_name = var.services_range_name

  # Gateway scope (regional or null)
  gateway_scope = var.gateway_scope

  depends_on = [module.foundation]
}

# Phase 2.5: GKE Node Service Account - Dedicated SA for node pools
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

# Phase 3: GKE Clusters - Multiple clusters with for_each pattern
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
  deletion_protection = lookup(each.value, "deletion_protection", false)

  # Secret sync configuration for syncing secrets from Secret Manager to the cluster
  secret_sync_config = lookup(each.value, "secret_sync_config", null)

  # Use dedicated service account for nodes
  node_service_account = module.gke_node_service_account.email

  depends_on = [module.networking, module.gke_node_service_account]
}

# Phase 4: Semantic Cache - Vertex AI + Apigee (parallel with GKE Clusters)
module "semantic_cache" {
  count  = var.enable_semantic_cache ? 1 : 0
  source = "./modules/semantic-cache"

  project_id = var.project_id
  region     = var.region
  vpc_id     = module.networking.network_id

  # Apigee Configuration (object-based)
  apigee = {
    organization = {
      display_name        = var.apigee_org_display_name
      description         = var.apigee_org_description
      billing_type        = var.apigee_billing_type
      analytics_region    = coalesce(var.apigee_analytics_region, var.region)
      runtime_type        = var.apigee_runtime_type
      disable_vpc_peering = var.apigee_disable_vpc_peering
    }
    envgroups            = local.final_apigee_envgroups
    environments         = var.apigee_environments
    instances            = var.apigee_instances
    endpoint_attachments = var.apigee_endpoint_attachments
  }

  # Vertex AI Configuration (object-based)
  vertex_ai = {
    index = {
      dimensions = var.vertex_ai_index_dimensions
    }
    deployed_index = {
      id                = local.deployed_index_id
      min_replica_count = var.vertex_ai_min_replica_count
      max_replica_count = var.vertex_ai_max_replica_count
    }
  }

  # Service account configuration
  create_service_accounts       = true
  enable_apim_workload_identity = false

  labels = var.labels

  depends_on = [module.networking, module.foundation]
}

# APIM Operator Workload Identity binding
# Managed here to depend on GKE clusters (ensures Identity Pool exists)
resource "google_service_account_iam_member" "apim_workload_identity" {
  count              = var.enable_semantic_cache ? 1 : 0
  service_account_id = module.semantic_cache[0].apim_operator_sa_name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[apim/apim-ksa]"

  depends_on = [module.gke_clusters]
}

# Grant Vertex AI Service Agent object access on the index data bucket only
# Required for Index creation and deployment (read source data, write index artifacts)
resource "google_storage_bucket_iam_member" "vertex_ai_agent_index_bucket" {
  count  = var.enable_semantic_cache ? 1 : 0
  bucket = module.semantic_cache[0].vertex_ai_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:service-${module.foundation.project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com"

  depends_on = [module.foundation]
}

# Phase 5: Storage - GCS Buckets (parallel with GKE Clusters)
module "storage" {
  source = "./modules/storage"

  project_id     = var.project_id
  project_number = module.foundation.project_number
  region         = var.region

  depends_on = [module.foundation]
}

# IAM binding to allow GKE workloads to access the bucket
# Managed here to depend on GKE clusters (ensures Identity Pool exists)
resource "google_storage_bucket_iam_member" "gke_storage_access" {
  bucket = module.storage.bucket_name
  role   = "roles/storage.objectViewer"
  member = "principal://iam.googleapis.com/projects/${module.foundation.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/default/sa/default"

  depends_on = [module.gke_clusters]
}

# Hugging Face Token Secret
resource "google_secret_manager_secret" "huggingface_token" {
  count     = var.huggingface_token != null ? 1 : 0
  project   = var.project_id
  secret_id = var.huggingface_secret_id

  labels = {
    purpose    = "model-downloads"
    managed-by = "terraform"
  }

  replication {
    auto {}
  }

  depends_on = [module.foundation]
}

# Secret Version
resource "google_secret_manager_secret_version" "huggingface_token" {
  count       = var.huggingface_token != null ? 1 : 0
  secret      = google_secret_manager_secret.huggingface_token[0].id
  secret_data = var.huggingface_token
}

# IAM binding to allow GKE workloads to access the secret via Workload Identity
# Uses principalSet:// format to grant access to all identities in the namespace
resource "google_secret_manager_secret_iam_member" "workload_identity_access" {
  for_each  = nonsensitive(var.huggingface_token != null) ? toset(var.model_namespaces) : toset([])
  project   = var.project_id
  secret_id = google_secret_manager_secret.huggingface_token[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principalSet://iam.googleapis.com/projects/${module.foundation.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/namespace/${each.value}"

  # Ensure GKE clusters with Workload Identity are created first
  depends_on = [module.gke_clusters, google_secret_manager_secret.huggingface_token]
}

# IAM binding for Custom Metrics Stackdriver Adapter Workload Identity
# Allows the custom-metrics-stackdriver-adapter service account to read Cloud Monitoring metrics
# Required for HPA to scale based on Prometheus/GMP metrics
resource "google_project_iam_member" "custom_metrics_adapter_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "principal://iam.googleapis.com/projects/${module.foundation.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/custom-metrics/sa/custom-metrics-stackdriver-adapter"

  # Ensure GKE clusters with Workload Identity are created first
  depends_on = [module.gke_clusters]
}

# Artifact Registry for Docker images
module "artifact_registry" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/artifact-registry?ref=v53.0.0"
  project_id = var.project_id
  location   = var.region
  name       = var.artifact_registry_name
  format = {
    docker = {
      standard = {
        immutable_tags = var.artifact_registry_immutable_tags
      }
    }
  }
  description = var.artifact_registry_description
  labels = {
    managed-by = "terraform"
  }

  depends_on = [module.foundation]
}

# Phase 6: Certificates - SSL/TLS Certificates
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

# Phase 7: DNS - DNS Zones and Records
module "dns" {
  count  = var.dns_zone_domain != null ? 1 : 0
  source = "./modules/dns"

  project_id                 = var.project_id
  dns_zone_domain            = var.dns_zone_domain
  dns_zone_name              = var.dns_zone_name
  enable_certificate_manager = var.enable_certificate_manager

  # Use explicit map structure for DNS authorizations to ensure keys are known at plan time
  certificate_dns_authorizations_regional = var.enable_certificate_manager && var.gateway_scope == "regional" ? {
    "primary"  = module.certificates[0].regional_dns_authorizations["${replace(trimsuffix(var.dns_zone_domain, "."), ".", "-")}-regional"]
    "internal" = module.certificates[0].regional_dns_authorizations["internal-auth-regional"]
  } : null

  # Internal IPs
  internal_gateway_ip = module.networking.internal_gateway_ip

  # Self Managed Inference Gateway IP (regional external ALB only)
  # Use preferred_gateway_ip which returns HTTPS IP when HTTPS is enabled
  enable_self_managed_gateway_dns = var.self_managed_gateway != null
  self_managed_gateway_ip         = var.self_managed_gateway != null ? module.self_managed_inference_gateway[0].preferred_gateway_ip : null
  self_managed_gateway_subdomain  = local.self_managed_gateway_subdomain

  # Self Managed Inference Gateway Internal DNS (for pod-to-gateway resolution)
  enable_self_managed_internal_dns = var.self_managed_gateway != null
  self_managed_internal_subdomain  = local.self_managed_gateway_subdomain

  # GKE Inference Gateway IP (uses internal IP from networking module)
  enable_gke_gateway_dns = var.gke_gateway != null
  gke_gateway_ip         = var.gke_gateway != null ? module.networking.internal_gateway_ip : null
  gke_gateway_subdomain  = var.gke_gateway != null ? split(".", var.gke_gateway.gateway.hostname)[0] : null

  # VPC for private DNS zone
  vpc_self_links = [module.networking.network_self_link]

  depends_on = [module.networking, module.certificates]
}

# Phase 8: Model Armor - Security Templates and IAM
module "model_armor" {
  count  = var.enable_model_armor ? 1 : 0
  source = "./modules/model-armor"

  project_id = var.project_id
  region     = var.region

  enable_model_armor = var.enable_model_armor
  template_id        = var.model_armor_template_id

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

  depends_on = [module.foundation]
}

# ==============================================================================
# PHASE 11: SELF MANAGED INFERENCE GATEWAY
# ==============================================================================
# Self-managed Regional Load Balancer with body-based routing.
# Uses object-based configuration for clean, maintainable code.

module "self_managed_inference_gateway" {
  count  = var.self_managed_gateway != null ? 1 : 0
  source = "./modules/self-managed-inference-gateway"

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.self_managed_gateway.name_prefix

  # Domain configuration (object)
  domain = var.self_managed_gateway.domain

  # VPC configuration (object) - subnet_id for VIP, proxy_subnet_id for LB proxies
  vpc = {
    id                = module.networking.network_id
    name              = module.networking.network_name
    subnet_id         = module.networking.subnet_id
    proxy_subnet_id   = module.networking.proxy_subnet_id
    proxy_subnet_cidr = var.proxy_subnet_cidr
  }

  # Internal load balancer configuration (object)
  load_balancer = var.self_managed_gateway.load_balancer

  # Flexible backends configuration (object)
  backends = var.self_managed_gateway.backends

  # Flexible routing configuration (object)
  routing = var.self_managed_gateway.routing

  # Body-based routing configuration (object)
  body_based_routing = var.self_managed_gateway.body_based_routing

  # Security configuration (object)
  security = var.self_managed_gateway.security

  # Health check configuration (object)
  health_check = var.self_managed_gateway.health_check

  # Firewall configuration (object)
  firewall = var.self_managed_gateway.firewall

  # Logging configuration (object)
  logging = var.self_managed_gateway.logging

  # Labels
  labels = var.labels

  depends_on = [module.networking]
}
