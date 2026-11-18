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

output "on_prem_vpc_network_name" {
  description = "The name of the on-prem VPC network."
  value       = module.vpcs["on_prem"].network_name
}

output "prod_vpc_names" {
  description = "The names of the Production VPCs."
  value = {
    transit  = module.vpcs["prod_transit"].network_name
    services = module.vpcs["prod_services"].network_name
    app1     = module.vpcs["prod_app1"].network_name
    app2     = module.vpcs["prod_app2"].network_name
    app3     = module.vpcs["prod_app3"].network_name
  }
}

output "vpc_self_links" {
  description = "Self-links of all provisioned VPC networks."
  value = {
    on_prem  = module.vpcs["on_prem"].network_self_link
    transit  = module.vpcs["prod_transit"].network_self_link
    services = module.vpcs["prod_services"].network_self_link
    app1     = module.vpcs["prod_app1"].network_self_link
    app2     = module.vpcs["prod_app2"].network_self_link
    app3     = module.vpcs["prod_app3"].network_self_link
  }
}

output "subnets" {
  description = "Map of subnet self-links keyed by '<region>/<subnet_name>' per VPC."
  value = {
    on_prem  = { for k, v in module.subnets["on_prem"].subnets : k => v.self_link }
    transit  = { for k, v in module.subnets["prod_transit"].subnets : k => v.self_link }
    services = { for k, v in module.subnets["prod_services"].subnets : k => v.self_link }
    app1     = { for k, v in module.subnets["prod_app1"].subnets : k => v.self_link }
    app2     = { for k, v in module.subnets["prod_app2"].subnets : k => v.self_link }
    app3     = { for k, v in module.subnets["prod_app3"].subnets : k => v.self_link }
  }
}

output "prod_service_project_ids" {
  description = "The IDs of the Production service projects."
  value = {
    for key, proj in module.prod_service_projects : key => proj.project_id
  }
}

output "project_ids" {
  description = "Discovered and created project IDs across environments."
  value = {
    on_prem      = local.on_prem_project_id
    prod_host    = local.prod_host_project_id
    prod_transit = local.prod_transit_project_id
    prod_service = {
      for key, proj in module.prod_service_projects : key => proj.project_id
    }
  }
}

output "ncc_hub_id" {
  description = "The ID of the Production NCC Hub (null if enable_ncc is false)."
  value       = var.enable_ncc ? module.ncc[0].ncc_hub.id : null
}

output "vpc_peerings" {
  description = "Map of VPC Network Peering names between prod_transit and application VPCs (empty if enable_vpc_peering is false)."
  value = {
    for k, v in local.vpc_peerings : k => {
      transit_to_spoke = google_compute_network_peering.transit_to_spoke[k].name
      spoke_to_transit = google_compute_network_peering.spoke_to_transit[k].name
    }
  }
}

output "hierarchical_firewall_policy_id" {
  description = "The ID of the L1 base folder Hierarchical Firewall Policy."
  value       = google_compute_firewall_policy.hierarchical.id
}

output "network_firewall_policies" {
  description = "Map of Global Network Firewall Policy names keyed by VPC."
  value = {
    for k, policy in google_compute_network_firewall_policy.vpc_policies : k => policy.name
  }
}

output "firewall_secure_tags" {
  description = "Map of Firewall Secure Tag value IDs (tagValues/<id>) for quarantine and workloads."
  value = merge(
    {
      quarantine = google_tags_tag_value.fw_quarantine_true.id
    },
    {
      for k, v in google_tags_tag_value.fw_workload : k => v.id
    }
  )
}
