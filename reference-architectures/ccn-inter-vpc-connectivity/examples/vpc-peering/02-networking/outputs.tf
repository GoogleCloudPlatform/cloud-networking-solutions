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
  value       = module.networking.on_prem_vpc_network_name
}

output "prod_vpc_names" {
  description = "The names of the Production VPCs."
  value       = module.networking.prod_vpc_names
}

output "vpc_self_links" {
  description = "Self-links of all provisioned VPC networks."
  value       = module.networking.vpc_self_links
}

output "subnets" {
  description = "Map of subnet self-links keyed by '<region>/<subnet_name>' per VPC."
  value       = module.networking.subnets
}

output "prod_service_project_ids" {
  description = "The IDs of the Production service projects."
  value       = module.networking.prod_service_project_ids
}

output "project_ids" {
  description = "Discovered and created project IDs across environments."
  value       = module.networking.project_ids
}

output "ncc_hub_id" {
  description = "The ID of the Production NCC Hub (null if enable_ncc is false)."
  value       = module.networking.ncc_hub_id
}

output "vpc_peerings" {
  description = "Map of VPC Network Peering names between prod_transit and application VPCs (empty if enable_vpc_peering is false)."
  value       = module.networking.vpc_peerings
}

output "hierarchical_firewall_policy_id" {
  description = "The ID of the L1 base folder Hierarchical Firewall Policy."
  value       = module.networking.hierarchical_firewall_policy_id
}

output "network_firewall_policies" {
  description = "Map of Global Network Firewall Policy names keyed by VPC."
  value       = module.networking.network_firewall_policies
}

output "firewall_secure_tags" {
  description = "Map of Firewall Secure Tag value IDs (tagValues/<id>) for quarantine and workloads."
  value       = module.networking.firewall_secure_tags
}
