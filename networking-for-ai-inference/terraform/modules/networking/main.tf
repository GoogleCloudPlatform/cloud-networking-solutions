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
 * Networking Module
 *
 * Creates VPC network, subnets, Cloud NAT, and static IP addresses for gateways.
 * Supports regional internal gateway configuration.
 */

# Get available zones in the region
data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region
}

# VPC Network
module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v53.0.0"
  project_id = var.project_id
  name       = var.vpc_name

  subnets = [
    {
      name          = var.subnet_name
      region        = var.region
      ip_cidr_range = var.primary_subnet_cidr
      secondary_ip_ranges = {
        (var.pods_range_name) = {
          ip_cidr_range = var.pods_cidr
        }
        (var.services_range_name) = {
          ip_cidr_range = var.services_cidr
        }
      }
    }
  ]

  subnets_proxy_only = [
    {
      name          = "${var.name_prefix}-proxy-subnet"
      region        = var.region
      ip_cidr_range = var.proxy_subnet_cidr
      active        = true
    }
  ]
}

# Cloud Router for NAT
resource "google_compute_router" "nat_router" {
  name    = "${var.name_prefix}-nat-router"
  project = var.project_id
  network = module.vpc.self_link
  region  = var.region
}

# Cloud NAT for outbound internet access from private nodes
resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${var.name_prefix}-nat-gateway"
  project                            = var.project_id
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Internal static IP addresses for internal L7 load balancers
# Purpose must be SHARED_LOADBALANCER_VIP for Gateway API compatibility
resource "google_compute_address" "internal_gateway" {
  count        = var.gateway_scope == "regional" ? 1 : 0
  name         = "${var.name_prefix}-internal-gateway-ip"
  project      = var.project_id
  region       = var.region
  subnetwork   = module.vpc.subnet_self_links["${var.region}/${var.subnet_name}"]
  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
  description  = "Internal static IP for internal gateway"
}
