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
  nat_routers = merge([
    for vpc_key, cfg in local.vpc_subnets : {
      for region in toset([for s in cfg.subnets : s.subnet_region]) : "${vpc_key}-${region}" => {
        project_id  = cfg.project_id
        network     = module.vpcs[vpc_key].network.self_link
        region      = region
        router_name = "${cfg.network_name}-nat-cr-${region}"
        nat_name    = "${cfg.network_name}-nat-${region}"
      }
    }
  ]...)
}

module "cloud_router_nat" {
  source   = "terraform-google-modules/cloud-router/google"
  version  = "~> 9.0"
  for_each = local.nat_routers

  name       = each.value.router_name
  project_id = each.value.project_id
  region     = each.value.region
  network    = each.value.network

  nats = [
    {
      name                               = each.value.nat_name
      source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
      min_ports_per_vm                   = 4096
      log_config = {
        filter = "ERRORS_ONLY"
      }
    },
  ]
}
