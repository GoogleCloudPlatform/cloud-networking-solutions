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
  vpc_peerings = var.enable_vpc_peering ? {
    "app1" = {
      transit_peering_name = "peer-p-transit-to-app1"
      spoke_peering_name   = "peer-p-app1-to-transit"
      spoke_network        = module.vpcs["prod_app1"].network_self_link
    }
    "app2" = {
      transit_peering_name = "peer-p-transit-to-app2"
      spoke_peering_name   = "peer-p-app2-to-transit"
      spoke_network        = module.vpcs["prod_app2"].network_self_link
    }
    "app3" = {
      transit_peering_name = "peer-p-transit-to-app3"
      spoke_peering_name   = "peer-p-app3-to-transit"
      spoke_network        = module.vpcs["prod_app3"].network_self_link
    }
  } : {}
}

# ------------------
# Transit-to-Spoke VPC Network Peerings
# ------------------
resource "google_compute_network_peering" "transit_to_spoke" {
  for_each = local.vpc_peerings

  name                 = each.value.transit_peering_name
  network              = module.vpcs["prod_transit"].network_self_link
  peer_network         = each.value.spoke_network
  export_custom_routes = true
  import_custom_routes = true

  lifecycle {
    precondition {
      condition     = !(var.enable_ncc && var.enable_vpc_peering)
      error_message = "enable_ncc and enable_vpc_peering cannot both be set to true at the same time."
    }
  }
}

# ------------------
# Spoke-to-Transit VPC Network Peerings
# ------------------
resource "google_compute_network_peering" "spoke_to_transit" {
  for_each = local.vpc_peerings

  name                 = each.value.spoke_peering_name
  network              = each.value.spoke_network
  peer_network         = module.vpcs["prod_transit"].network_self_link
  export_custom_routes = true
  import_custom_routes = true

  depends_on = [google_compute_network_peering.transit_to_spoke]
}
