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
 * Creates VPC network, primary subnet, Agent Gateway dedicated subnet,
 * Cloud Router, Cloud NAT with a reserved static IP, and a firewall rule
 * allowing PSC-I ingress to the agent-gateway subnet.
 *
 * The SWP proxy-only subnet is provisioned separately in modules/secure-web-proxy
 * so that module owns the full lifecycle of the SWP and its required subnet.
 * A VPC region can only have one active REGIONAL_MANAGED_PROXY subnet, so the
 * two subnets must not both use role = "ACTIVE" in the same region.
 */

# VPC Network — primary subnet only; no proxy-only or PSC subnets here.
# The SWP module adds its own proxy-only subnet for SWP next-hop routing.
module "vpc" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v55.3.0"
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
}

# Agent Gateway — dedicated regular subnet that hosts the PSC-I network
# attachment the agent-gateway module creates.
resource "google_compute_subnetwork" "agent_gateway" {
  count                    = var.enable_agent_gateway ? 1 : 0
  project                  = var.project_id
  name                     = "${var.name_prefix}-agent-gateway-subnet"
  region                   = var.region
  network                  = module.vpc.self_link
  ip_cidr_range            = var.agent_gateway_subnet_cidr
  private_ip_google_access = true
}

# Reserve a static external IP for Cloud NAT. This is the address the MCP
# Cloud Run service (and any other public endpoint the agent reaches) will
# see as the source IP of all Agent Runtime egress.
resource "google_compute_address" "nat" {
  project      = var.project_id
  name         = "${var.name_prefix}-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
  description  = "Static IP for Cloud NAT egress — all Agent Runtime internet traffic exits from this address"
}

# Cloud Router for NAT. Note: the Secure Web Proxy in next-hop mode also
# auto-creates its own hidden Cloud Router in the same region. These are
# separate resources and both coexist safely; the SWP-managed router is
# deleted automatically when delete_swg_autogen_router_on_destroy = true
# on the gateway.
resource "google_compute_router" "nat_router" {
  name    = "${var.name_prefix}-nat-router"
  project = var.project_id
  network = module.vpc.self_link
  region  = var.region
}

# Cloud NAT — MANUAL_ONLY so all egress from the VPC uses the reserved static
# IP above. This is the mechanism that gives the agent a predictable source IP.
resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${var.name_prefix}-nat-gateway"
  project                            = var.project_id
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# =============================================================================
# Private Google Access DNS Override
# Required by Agent Gateway DNS Peering: the domain specified in dnsPeeringConfig
# ("googleapis.com.") must exist as a private managed zone in the target VPC.
# =============================================================================

resource "google_dns_managed_zone" "googleapis" {
  name        = "${var.name_prefix}-googleapis"
  dns_name    = "googleapis.com."
  description = "Private zone for googleapis.com required by Agent Gateway DNS peering"
  project     = var.project_id
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = module.vpc.self_link
    }
  }
}

resource "google_dns_record_set" "googleapis_cname" {
  name         = "*.googleapis.com."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  project      = var.project_id
  rrdatas      = ["googleapis.com."]
}

resource "google_dns_record_set" "googleapis_a" {
  name         = "googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  project      = var.project_id
  rrdatas      = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
}


