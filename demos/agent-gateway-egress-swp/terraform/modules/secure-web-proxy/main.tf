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
 * Secure Web Proxy (SWP) Module — Next-Hop Mode
 *
 * Deploys a Secure Web Proxy gateway in NEXT_HOP_ROUTING_MODE so that
 * Agent-Runtime egress (sourced from the Agent Gateway PSC-I subnet) is
 * steered through the proxy before exiting the VPC via Cloud NAT.
 *
 * Two policy-based routes implement the standard next-hop deployment pattern:
 *   1. Anti-loop route (higher priority): traffic sourced from the SWP's own
 *      proxy-only subnet exits via the default route, bypassing the proxy.
 *   2. Forced-next-hop route (lower priority): traffic sourced from the Agent
 *      Gateway subnet is redirected to the SWP gateway IP.
 *
 * TLS inspection is intentionally disabled (no certificate_urls set). The
 * gateway passes HTTP/HTTPS traffic through to Cloud NAT with the default
 * ALLOW policy rule — suitable for demonstration. See README extension points
 * for adding TLS inspection.
 *
 * Note: SWP auto-creates a hidden Cloud Router in the same region for its own
 * proxy egress. This is separate from the explicit Cloud Router created by the
 * networking module for Cloud NAT. Both coexist without conflict. Setting
 * delete_swg_autogen_router_on_destroy = true ensures the hidden router is
 * cleaned up when this gateway is destroyed.
 *
 * Reference: https://cloud.google.com/secure-web-proxy/docs/deploy-next-hop
 *
 * Subnet roles:
 *   - REGIONAL_MANAGED_PROXY subnet (google_compute_subnetwork.swp_proxy): required
 *     as a regional prerequisite for SWP to work; provides unique IPs for the proxy
 *     infrastructure. NOT referenced in google_network_services_gateway.subnetwork.
 *   - var.private_subnet_id (the primary PRIVATE subnet): referenced in
 *     google_network_services_gateway.subnetwork — this is where the gateway's
 *     internal next-hop IP is allocated. Must have Purpose = PRIVATE.
 *
 * API format notes:
 *   - google_network_services_gateway requires network and subnetwork in the
 *     short "projects/P/..." form, NOT the https:// self_link URL.
 *   - google_network_connectivity_policy_based_route also requires the short form.
 *     local.network_id strips the googleapis.com prefix from var.network_self_link.
 */

locals {
  # Convert full self_link URL to the short form required by policy-based routes.
  # Example: https://www.googleapis.com/compute/v1/projects/P/global/networks/N
  #       →  projects/P/global/networks/N
  network_id = replace(var.network_self_link, "https://www.googleapis.com/compute/v1/", "")
}

# Proxy-only subnet — regional prerequisite for SWP.
# purpose = REGIONAL_MANAGED_PROXY + role = ACTIVE must exist in the region
# for SWP to work. It provides unique IPs for the proxy infrastructure internally
# but is NOT the subnet referenced in google_network_services_gateway.subnetwork
# (that must be a PRIVATE subnet). Only one ACTIVE REGIONAL_MANAGED_PROXY subnet
# per VPC per region is allowed — the networking module omits this to avoid conflict.
resource "google_compute_subnetwork" "swp_proxy" {
  project       = var.project_id
  name          = "${var.name_prefix}-swp-proxy-subnet"
  region        = var.region
  network       = var.network_self_link
  ip_cidr_range = var.swp_proxy_subnet_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Delay destruction of the proxy-only subnet to give the SWP gateway time to fully release it.
resource "time_sleep" "wait_swp_proxy_subnet_release" {
  depends_on       = [google_compute_subnetwork.swp_proxy]
  destroy_duration = "180s"
}

# Gateway security policy — container for the security rules.
resource "google_network_security_gateway_security_policy" "swp" {
  provider    = google-beta
  project     = var.project_id
  name        = "${var.name_prefix}-swp-policy"
  location    = var.region
  description = "SWP security policy for Agent Gateway egress demo"
}

# Default ALLOW rule: passes all traffic through without TLS inspection.
# A session_matcher of "true" matches every request. Enabling TLS inspection
# (tls_inspect = true) requires a Certificate Manager certificate authority
# pool — see README extension points.
resource "google_network_security_gateway_security_policy_rule" "allow_all" {
  provider                = google-beta
  project                 = var.project_id
  name                    = "${var.name_prefix}-swp-allow-all"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp.name
  enabled                 = true
  priority                = 1000
  session_matcher         = "true"
  basic_profile           = "ALLOW"
}

# The Secure Web Proxy gateway in NEXT_HOP_ROUTING_MODE.
# In this mode the gateway acts as a transparent L7 proxy: policy-based routes
# direct matching traffic to the gateway's internal IP, the SWP applies the
# security policy, then forwards the traffic to the origin (and out via NAT).
# addresses is omitted — the gateway auto-assigns an internal IP from the
# proxy-only subnet. That IP is read back via .addresses[0] for the PBR below.
resource "google_network_services_gateway" "swp" {
  provider     = google-beta
  project      = var.project_id
  name         = "${var.name_prefix}-swp"
  location     = var.region
  type         = "SECURE_WEB_GATEWAY"
  routing_mode = "NEXT_HOP_ROUTING_MODE"
  ports        = [80, 443]

  gateway_security_policy = google_network_security_gateway_security_policy.swp.id
  # Both network and subnetwork must use the short "projects/P/..." form.
  # subnetwork must be a PRIVATE-purpose subnet — the REGIONAL_MANAGED_PROXY
  # subnet above is a regional prerequisite but cannot be used here.
  network    = local.network_id
  subnetwork = var.private_subnet_id

  # SWP auto-creates a Cloud Router for its own proxy-originated egress.
  # This flag ensures that hidden router is removed when the gateway is
  # destroyed, preventing orphaned routers accumulating across re-applies.
  delete_swg_autogen_router_on_destroy = true

  depends_on = [
    google_network_security_gateway_security_policy_rule.allow_all,
    time_sleep.wait_swp_proxy_subnet_release
  ]
}

# Policy-Based Route 1 — Anti-loop.
# Scope: traffic sourced FROM the SWP's own proxy-only subnet.
# Action: exit via the default route (internet gateway) rather than looping
# back through the SWP.
# Priority 1000 (higher priority = lower number is evaluated first, but PBRs
# use ascending priority where lower number wins; 1000 < 2000 so this wins for
# proxy-originated traffic).
resource "google_network_connectivity_policy_based_route" "swp_anti_loop" {
  project     = var.project_id
  name        = "${var.name_prefix}-pbr-swp-antiloop"
  description = "Anti-loop: SWP proxy-own traffic exits via default route, not back through SWP"
  network     = local.network_id

  filter {
    protocol_version = "IPV4"
    src_range        = var.swp_proxy_subnet_cidr
  }

  priority              = 1000
  next_hop_other_routes = "DEFAULT_ROUTING"
}

# Policy-Based Route 2 — Forced next-hop through SWP.
# Scope: traffic sourced FROM the Agent Gateway PSC-I subnet heading to the
# public internet (0.0.0.0/0). This covers all Agent Runtime egress.
# Action: forward to the SWP gateway's internal IP.
# Priority 2000 (evaluated after the anti-loop rule above).
resource "google_network_connectivity_policy_based_route" "agw_to_swp" {
  project     = var.project_id
  name        = "${var.name_prefix}-pbr-agw-to-swp"
  description = "Force Agent Gateway PSC-I egress through Secure Web Proxy"
  network     = local.network_id

  filter {
    protocol_version = "IPV4"
    src_range        = var.agent_gateway_subnet_cidr
    dest_range       = "0.0.0.0/0"
  }

  priority        = 2000
  next_hop_ilb_ip = google_network_services_gateway.swp.addresses[0]

  depends_on = [google_network_services_gateway.swp]
}

# Policy-Based Route 1b — Private Google Access bypass.
# Scope: traffic from the Agent Gateway subnet heading to the
# private.googleapis.com VIP (199.36.153.8/30).
# Action: exit via the default route (Private Google Access, no NAT) so the
# Reasoning Engine can reach internal Google API endpoints.
# Priority 1500 — evaluated after anti-loop (1000) but BEFORE the SWP redirect
# (2000), so googleapis traffic bypasses the SWP and Cloud NAT entirely.
resource "google_network_connectivity_policy_based_route" "googleapis_restricted_bypass" {
  project     = var.project_id
  name        = "${var.name_prefix}-pbr-googleapis-private-bypass"
  description = "Bypass SWP for private.googleapis.com VIP"
  network     = local.network_id

  filter {
    protocol_version = "IPV4"
    src_range        = var.agent_gateway_subnet_cidr
    dest_range       = "199.36.153.8/30"
  }

  priority              = 1500
  next_hop_other_routes = "DEFAULT_ROUTING"
}




