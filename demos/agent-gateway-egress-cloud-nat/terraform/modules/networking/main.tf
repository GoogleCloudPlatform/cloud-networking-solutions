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
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v59.0.0"
  project_id   = var.project_id
  name         = var.vpc_name
  routing_mode = "REGIONAL"
  description  = ""

  subnets = [
    {
      name          = var.subnet_name
      region        = var.region
      ip_cidr_range = var.primary_subnet_cidr
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

  subnets_psc = [
    {
      name          = "${var.name_prefix}-psc-subnet"
      region        = var.region
      ip_cidr_range = var.psc_subnet_cidr
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
  
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.static_address.self_link]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.agent_gateway.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_address" "static_address" {
  project = var.project_id
  name   = "${var.name_prefix}-address"
  region = var.region
  address_type = "EXTERNAL"
}

# PSC Interface — dedicated regular subnet for network attachment
resource "google_compute_subnetwork" "psc_interface" {
  count                    = var.enable_psc_interface ? 1 : 0
  project                  = var.project_id
  name                     = "${var.name_prefix}-psc-interface-subnet"
  region                   = var.region
  network                  = module.vpc.self_link
  ip_cidr_range            = var.psc_interface_subnet_cidr
  private_ip_google_access = true
}

# PSC Interface — network attachment with automatic acceptance
resource "google_compute_network_attachment" "psc_interface" {
  count                 = var.enable_psc_interface ? 1 : 0
  project               = var.project_id
  name                  = "${var.name_prefix}-psc-interface-attachment"
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [google_compute_subnetwork.psc_interface[0].self_link]
}

# PSC Interface — firewall rule allowing ingress from PSC-I subnet
resource "google_compute_firewall" "psc_interface_allow" {
  count         = var.enable_psc_interface ? 1 : 0
  project       = var.project_id
  name          = "${var.name_prefix}-allow-psc-interface"
  network       = module.vpc.self_link
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.psc_interface_subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = ["22", "443"]
  }
  allow {
    protocol = "icmp"
  }
}

# Agent Gateway — dedicated regular subnet that hosts both the Agent Gateway
# PSC-Interface network attachment and the relocated MCP internal LB VIP.
# Co-locating them satisfies the demo's "same subnet" requirement and keeps the
# PSC-I egress range outside the documented Agent Gateway exclusions.
resource "google_compute_subnetwork" "agent_gateway" {
  project       = var.project_id
  name          = "${var.name_prefix}-agent-gateway-subnet"
  region        = var.region
  network       = module.vpc.self_link
  ip_cidr_range = var.agent_gateway_subnet_cidr
}
