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
# FIREWALL RULES
# ==============================================================================
#
# This file defines firewall rules to allow:
# - Health check traffic from Google Cloud load balancers
# - Load balancer proxy traffic to backends
#
# ==============================================================================

# ==============================================================================
# ALLOW HEALTH CHECK TRAFFIC
# ==============================================================================

resource "google_compute_firewall" "health_checks" {
  count = var.firewall.create_rules ? 1 : 0

  name        = local.firewall_health_checks_name
  project     = var.project_id
  network     = var.vpc.name
  description = "Allow health check traffic from Google Cloud load balancers"

  # Allow ingress from Google Cloud health check IP ranges
  direction = "INGRESS"
  priority  = 1000

  source_ranges = var.firewall.health_check_ranges

  # Allow traffic to all backend services
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8000", "8080", "9000-9010"]
  }

  # Log configuration
  log_config {
    metadata = var.logging.enable_access_logs ? "INCLUDE_ALL_METADATA" : "EXCLUDE_ALL_METADATA"
  }
}

# ==============================================================================
# ALLOW PROXY SUBNET TRAFFIC
# ==============================================================================
# Regional Internal Application Load Balancers (INTERNAL_MANAGED) route data
# plane traffic through managed envoy proxies in the proxy-only subnet. This
# firewall rule allows that traffic to reach backend endpoints.

resource "google_compute_firewall" "proxy_traffic" {
  count = var.firewall.create_rules && var.vpc.proxy_subnet_cidr != null ? 1 : 0

  name        = local.firewall_proxy_traffic_name
  project     = var.project_id
  network     = var.vpc.name
  description = "Allow traffic from proxy-only subnet to backends for INTERNAL_MANAGED LB"

  direction = "INGRESS"
  priority  = 1000

  source_ranges = [var.vpc.proxy_subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8000", "8080", "9000-9010"]
  }

  log_config {
    metadata = var.logging.enable_access_logs ? "INCLUDE_ALL_METADATA" : "EXCLUDE_ALL_METADATA"
  }
}
