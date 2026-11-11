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
  vpc_spokes = var.enable_ncc ? {
    "spoke-p-vpc-transit" = {
      project_id = local.prod_transit_project_id
      uri        = "projects/${local.prod_transit_project_id}/global/networks/${module.vpcs["prod_transit"].network_name}"
    }
    "spoke-p-vpc-app1" = {
      project_id = local.prod_host_project_id
      uri        = "projects/${local.prod_host_project_id}/global/networks/${module.vpcs["prod_app1"].network_name}"
    }
    "spoke-p-vpc-app2" = {
      project_id = local.prod_host_project_id
      uri        = "projects/${local.prod_host_project_id}/global/networks/${module.vpcs["prod_app2"].network_name}"
    }
    "spoke-p-vpc-app3" = {
      project_id = local.prod_host_project_id
      uri        = "projects/${local.prod_host_project_id}/global/networks/${module.vpcs["prod_app3"].network_name}"
    }
  } : {}
}

# Create NCC Hub and Hybrid Spokes
module "ncc" {
  count   = var.enable_ncc ? 1 : 0
  source  = "terraform-google-modules/network/google//modules/network-connectivity-center"
  version = "~> 18.0"

  project_id              = local.prod_transit_project_id
  ncc_hub_name            = "ncc-hub-prod"
  ncc_hub_description     = "Production NCC Hub for on-prem and VPC connectivity"
  ncc_hub_labels          = local.labels
  spoke_labels            = local.labels
  ncc_hub_preset_topology = "MESH"
  ncc_hub_policy_mode     = "PRESET"
  export_psc              = true

  # Required for auto accepting VPC spokes from host project
  ncc_groups = {
    "default" = {
      name        = "default"
      description = "Default MESH group with auto-accept for host project"
      auto_accept_projects = [
        local.prod_host_project_id,
        local.prod_transit_project_id
      ]
    }
  }

  # Hybrid spokes (VPNs)
  hybrid_spokes = {
    for key, link in local.vpn_links :
    link.spoke_name => {
      location                   = link.region
      type                       = "vpn"
      uris                       = [for t in module.vpn_transit[key].tunnels : t.self_link]
      site_to_site_data_transfer = true
      include_import_ranges      = ["ALL_IPV4_RANGES"]
      group                      = "default"
    }
  }
}

# VPC Spokes (Created after module.ncc configures auto_accept_projects on the
# default group so cross-project spokes in the host project are auto-accepted
# instead of entering PENDING_REVIEW)
resource "google_network_connectivity_spoke" "vpc_spokes" {
  for_each = local.vpc_spokes

  project  = each.value.project_id
  name     = each.key
  location = "global"
  hub      = module.ncc[0].ncc_hub.id
  group    = module.ncc[0].groups["default"].id
  labels   = local.labels

  linked_vpc_network {
    uri = each.value.uri
  }

  lifecycle {
    precondition {
      condition     = !(var.enable_ncc && var.enable_vpc_peering)
      error_message = "enable_ncc and enable_vpc_peering cannot both be set to true at the same time."
    }
  }
}
