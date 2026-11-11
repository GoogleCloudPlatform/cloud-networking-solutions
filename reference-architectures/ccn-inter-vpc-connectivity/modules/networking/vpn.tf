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

locals {
  bgp_asns = {
    on_prem  = 65001
    transit  = 65002
    services = 65003
  }

  routers = {
    on_prem_use4 = {
      name       = "router-vpn-on-prem-use4"
      project_id = local.on_prem_project_id
      network    = module.vpcs["on_prem"].network_name
      region     = var.regions.primary
      asn        = local.bgp_asns.on_prem
    }
    on_prem_usw1 = {
      name       = "router-vpn-on-prem-usw1"
      project_id = local.on_prem_project_id
      network    = module.vpcs["on_prem"].network_name
      region     = var.regions.secondary
      asn        = local.bgp_asns.on_prem
    }
    transit_use4 = {
      name       = "router-vpn-p-transit-use4"
      project_id = local.prod_transit_project_id
      network    = module.vpcs["prod_transit"].network_name
      region     = var.regions.primary
      asn        = local.bgp_asns.transit
    }
    transit_usw1 = {
      name       = "router-vpn-p-transit-usw1"
      project_id = local.prod_transit_project_id
      network    = module.vpcs["prod_transit"].network_name
      region     = var.regions.secondary
      asn        = local.bgp_asns.transit
    }
    services_use4 = {
      name       = "router-vpn-p-svcs-use4"
      project_id = local.prod_host_project_id
      network    = module.vpcs["prod_services"].network_name
      region     = var.regions.primary
      asn        = local.bgp_asns.services
    }
    services_usw1 = {
      name       = "router-vpn-p-svcs-usw1"
      project_id = local.prod_host_project_id
      network    = module.vpcs["prod_services"].network_name
      region     = var.regions.secondary
      asn        = local.bgp_asns.services
    }
  }

  vpn_links = {
    onprem_use4 = {
      region              = var.regions.primary
      spoke_name          = "spoke-p-hybrid-vpn-onprem-use4"
      transit_gw_name     = "gw-p-transit-use4"
      transit_router_key  = "transit_use4"
      transit_tunnel_pref = "tunnel-transit-to-on-prem-use4"
      peer_project_id     = local.on_prem_project_id
      peer_network        = module.vpcs["on_prem"].network_name
      peer_gw_name        = "gw-on-prem-use4"
      peer_router_key     = "on_prem_use4"
      peer_asn            = local.bgp_asns.on_prem
      peer_tunnel_pref    = "tunnel-on-prem-to-transit-use4"
      bgp_octets          = [0, 1] # 169.254.0.0/30 and 169.254.1.0/30
    }
    onprem_usw1 = {
      region              = var.regions.secondary
      spoke_name          = "spoke-p-hybrid-vpn-onprem-usw1"
      transit_gw_name     = "gw-p-transit-usw1"
      transit_router_key  = "transit_usw1"
      transit_tunnel_pref = "tunnel-transit-to-on-prem-usw1"
      peer_project_id     = local.on_prem_project_id
      peer_network        = module.vpcs["on_prem"].network_name
      peer_gw_name        = "gw-on-prem-usw1"
      peer_router_key     = "on_prem_usw1"
      peer_asn            = local.bgp_asns.on_prem
      peer_tunnel_pref    = "tunnel-on-prem-to-transit-usw1"
      bgp_octets          = [2, 3] # 169.254.2.0/30 and 169.254.3.0/30
    }
    services_use4 = {
      region              = var.regions.primary
      spoke_name          = "spoke-p-hybrid-vpn-svcs-use4"
      transit_gw_name     = "gw-p-transit-to-svcs-use4"
      transit_router_key  = "transit_use4"
      transit_tunnel_pref = "tunnel-transit-to-svcs-use4"
      peer_project_id     = local.prod_host_project_id
      peer_network        = module.vpcs["prod_services"].network_name
      peer_gw_name        = "gw-p-svcs-to-transit-use4"
      peer_router_key     = "services_use4"
      peer_asn            = local.bgp_asns.services
      peer_tunnel_pref    = "tunnel-svcs-to-transit-use4"
      bgp_octets          = [4, 5] # 169.254.4.0/30 and 169.254.5.0/30
    }
    services_usw1 = {
      region              = var.regions.secondary
      spoke_name          = "spoke-p-hybrid-vpn-svcs-usw1"
      transit_gw_name     = "gw-p-transit-to-svcs-usw1"
      transit_router_key  = "transit_usw1"
      transit_tunnel_pref = "tunnel-transit-to-svcs-usw1"
      peer_project_id     = local.prod_host_project_id
      peer_network        = module.vpcs["prod_services"].network_name
      peer_gw_name        = "gw-p-svcs-to-transit-usw1"
      peer_router_key     = "services_usw1"
      peer_asn            = local.bgp_asns.services
      peer_tunnel_pref    = "tunnel-svcs-to-transit-usw1"
      bgp_octets          = [6, 7] # 169.254.6.0/30 and 169.254.7.0/30
    }
  }
}

# ------------------
# Cloud Routers
# ------------------
resource "google_compute_router" "routers" {
  for_each = local.routers

  project = each.value.project_id
  name    = each.value.name
  network = each.value.network
  region  = each.value.region

  bgp {
    asn = each.value.asn
  }
}

# ------------------
# Peer-Side HA VPN Gateways
# (Created outside module.vpn_peer to avoid a circular dependency between
#  for_each module close nodes module.vpn_transit and module.vpn_peer)
# ------------------
resource "google_compute_ha_vpn_gateway" "peer" {
  for_each = local.vpn_links

  name    = each.value.peer_gw_name
  project = each.value.peer_project_id
  region  = each.value.region
  network = each.value.peer_network
  labels  = local.labels
}

# ------------------
# Transit-Side HA VPN Gateways & Tunnels
# ------------------
module "vpn_transit" {
  source   = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version  = "~> 6.1"
  for_each = local.vpn_links

  project_id       = local.prod_transit_project_id
  network          = module.vpcs["prod_transit"].network_name
  region           = each.value.region
  name             = each.value.transit_gw_name
  peer_gcp_gateway = google_compute_ha_vpn_gateway.peer[each.key].self_link
  router_name      = google_compute_router.routers[each.value.transit_router_key].name
  labels           = local.labels

  tunnels = {
    for idx, octet in each.value.bgp_octets :
    "${each.value.transit_tunnel_pref}-if${idx}" => {
      bgp_peer = {
        address = "169.254.${octet}.2"
        asn     = each.value.peer_asn
      }
      bgp_session_range     = "169.254.${octet}.1/30"
      vpn_gateway_interface = idx
    }
  }
}

# ------------------
# Peer-Side (On-Prem & Services) VPN Tunnels & BGP Peers
# ------------------
module "vpn_peer" {
  source   = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version  = "~> 6.1"
  for_each = local.vpn_links

  project_id            = each.value.peer_project_id
  network               = each.value.peer_network
  region                = each.value.region
  name                  = each.value.peer_gw_name
  create_vpn_gateway    = false
  vpn_gateway_self_link = google_compute_ha_vpn_gateway.peer[each.key].self_link
  peer_gcp_gateway      = module.vpn_transit[each.key].self_link
  router_name           = google_compute_router.routers[each.value.peer_router_key].name
  labels                = local.labels

  tunnels = {
    for idx, octet in each.value.bgp_octets :
    "${each.value.peer_tunnel_pref}-if${idx}" => {
      bgp_peer = {
        address = "169.254.${octet}.1"
        asn     = local.bgp_asns.transit
      }
      bgp_session_range     = "169.254.${octet}.2/30"
      shared_secret         = module.vpn_transit[each.key].random_secret
      vpn_gateway_interface = idx
    }
  }
}
