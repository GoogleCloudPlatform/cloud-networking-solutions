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

# ==============================================================================
# BACKEND SERVICES AND NETWORK ENDPOINT GROUPS
# ==============================================================================
#
# This file creates backend services dynamically from the var.backends.services
# map. Supports multiple backend types:
# - GKE NEG (pass full self_link via group)
# - Internet NEG (auto-created when internet_fqdn is set)
# - Hybrid NEG (pass full self_link via group)
# - Serverless NEG (pass full self_link via group)
#
# ==============================================================================

# ==============================================================================
# INTERNET NEGS (Auto-created for FQDN backends)
# ==============================================================================

resource "google_compute_region_network_endpoint_group" "internet" {
  for_each = { for k, v in var.backends.services : k => v if v.internet_fqdn != null }

  name                  = "${local.resource_prefix}-${each.key}-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "INTERNET_FQDN_PORT"
  network               = var.vpc.id

  description = "Internet NEG for ${each.key} backend (${each.value.internet_fqdn})"
}

resource "google_compute_region_network_endpoint" "internet" {
  for_each = { for k, v in var.backends.services : k => v if v.internet_fqdn != null }

  project                       = var.project_id
  region                        = var.region
  region_network_endpoint_group = google_compute_region_network_endpoint_group.internet[each.key].name

  fqdn = each.value.internet_fqdn
  port = each.value.internet_port
}

# ==============================================================================
# GKE NEGS (Pre-created for GKE NEG controller adoption)
# ==============================================================================
# Terraform creates empty zonal NEGs. The GKE NEG controller discovers and
# adopts these existing NEGs, populating endpoints as pods come up.
# This eliminates the two-phase NEG discovery/sed/re-apply loop in deploy.sh.

locals {
  # Flatten backend+zone combinations into a map keyed by "backend_name/zone"
  gke_neg_instances = merge([
    for k, v in var.backends.services : {
      for zone in(v.gke_neg != null ? v.gke_neg.zones : []) :
      "${k}/${zone}" => {
        backend_name = k
        neg_name     = v.gke_neg.name
        zone         = zone
        network      = coalesce(try(v.gke_neg.network, null), var.vpc.id)
        subnetwork   = coalesce(try(v.gke_neg.subnetwork, null), var.vpc.subnet_id)
      }
    }
  ]...)
}

resource "google_compute_network_endpoint_group" "gke" {
  for_each = local.gke_neg_instances

  name                  = each.value.neg_name
  project               = var.project_id
  zone                  = each.value.zone
  network               = each.value.network
  subnetwork            = each.value.subnetwork
  network_endpoint_type = "GCE_VM_IP_PORT"
  default_port          = 0

  description = "GKE NEG for ${each.value.backend_name} backend (pre-created for NEG controller adoption)"

  lifecycle {
    ignore_changes = [default_port]
  }
}

locals {
  # Group NEG self_links by backend name for use in backend_groups resolution
  gke_neg_groups = {
    for k, v in var.backends.services : k => [
      for zone in v.gke_neg.zones :
      google_compute_network_endpoint_group.gke["${k}/${zone}"].self_link
    ] if v.gke_neg != null
  }
}

# ==============================================================================
# HEALTH CHECKS (For backends that specify health_check - HTTP)
# ==============================================================================

resource "google_compute_region_health_check" "backends" {
  for_each = { for k, v in var.backends.services : k => v if v.health_check != null }

  name    = "${local.resource_prefix}-${each.key}-hc"
  project = var.project_id
  region  = var.region

  check_interval_sec  = var.health_check.interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  http_health_check {
    port         = each.value.health_check.port
    request_path = each.value.health_check.path
  }

  description = "Health check for ${each.key} backend"
}

# ==============================================================================
# HEALTH CHECKS (For Internet NEG backends - HTTPS)
# ==============================================================================
# For Internet NEGs targeting Google APIs, we use a TCP health check since
# HTTPS checks to / typically don't return 200 OK.

resource "google_compute_region_health_check" "internet_backends" {
  for_each = { for k, v in var.backends.services : k => v if v.internet_fqdn != null && v.health_check == null }

  name    = "${local.resource_prefix}-${each.key}-hc"
  project = var.project_id
  region  = var.region

  check_interval_sec  = var.health_check.interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  # Use TCP health check for Internet NEGs - just checks connectivity
  tcp_health_check {
    port = each.value.internet_port
  }

  description = "TCP health check for ${each.key} Internet NEG backend"
}

# ==============================================================================
# BACKEND GROUPS (Resolves groups list for each backend service)
# ==============================================================================

locals {
  # For each backend, resolve the list of backend groups:
  # Priority: gke_neg > groups > internet_fqdn > empty
  # - If gke_neg is set, use pre-created zonal NEG self_links
  # - If groups is provided, use it directly (supports multi-zone NEGs)
  # - If internet_fqdn is set, use the auto-created internet NEG
  # - Otherwise, empty list
  backend_groups = {
    for k, v in var.backends.services : k => (
      v.gke_neg != null ? local.gke_neg_groups[k] : (
        v.groups != null ? v.groups : (
          v.internet_fqdn != null ? [google_compute_region_network_endpoint_group.internet[k].id] : []
        )
      )
    )
  }
}

# ==============================================================================
# BACKEND SERVICES
# ==============================================================================

resource "google_compute_region_backend_service" "backends" {
  for_each = var.backends.services

  name                  = "${local.resource_prefix}-${each.key}"
  project               = var.project_id
  region                = var.region
  protocol              = each.value.protocol
  load_balancing_scheme = local.lb_scheme
  timeout_sec           = each.value.timeout_sec

  dynamic "backend" {
    for_each = local.backend_groups[each.key]
    content {
      group                 = backend.value
      balancing_mode        = each.value.balancing_mode
      max_rate_per_endpoint = each.value.balancing_mode == "RATE" ? each.value.max_rate_per_endpoint : null
      capacity_scaler       = each.value.capacity_scaler
    }
  }

  # Health check - use explicit config only
  # Note: Internet NEGs don't require health checks (and health checks to external
  # endpoints may fail with INTERNAL_MANAGED load balancers)
  health_checks = each.value.health_check != null ? [
    google_compute_region_health_check.backends[each.key].id
  ] : null

  connection_draining_timeout_sec = var.load_balancer.connection_draining_timeout_sec

  log_config {
    enable      = var.logging.enable_access_logs
    sample_rate = var.logging.sample_rate
  }

  description = "Backend service for ${each.key}"
}

# ==============================================================================
# LOCAL VALUES FOR BACKEND REFERENCES
# ==============================================================================

locals {
  # Map of backend names to their IDs for URL map routing
  backend_ids = {
    for k, v in google_compute_region_backend_service.backends : k => v.id
  }

  # Default backend service ID
  default_backend_id = google_compute_region_backend_service.backends[var.backends.default].id
}
