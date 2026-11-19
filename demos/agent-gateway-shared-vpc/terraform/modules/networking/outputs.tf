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



output "network_id" {
  description = "VPC network ID"
  value       = module.vpc.id
}

output "network_name" {
  description = "VPC network name"
  value       = module.vpc.name
}

output "network_self_link" {
  description = "VPC network self link"
  value       = module.vpc.self_link
}

output "subnet_name" {
  description = "Primary subnet name"
  value       = var.subnet_name
}

output "subnet_id" {
  description = "Primary subnet ID"
  value       = module.vpc.subnet_ids["${var.region}/${var.subnet_name}"]
}

output "subnet_self_link" {
  description = "Primary subnet self link"
  value       = module.vpc.subnet_self_links["${var.region}/${var.subnet_name}"]
}

output "nat_static_ip" {
  description = "Reserved static external IP address used by Cloud NAT. All Agent Runtime egress exits from this address — this is what the public MCP server sees."
  value       = google_compute_address.nat.address
}

output "nat_static_ip_self_link" {
  description = "Self-link of the reserved NAT static IP address"
  value       = google_compute_address.nat.self_link
}

output "nat_router_name" {
  description = "Cloud Router name"
  value       = google_compute_router.nat_router.name
}

output "nat_gateway_name" {
  description = "Cloud NAT gateway name"
  value       = google_compute_router_nat.nat_gateway.name
}

# Agent Gateway dedicated subnet outputs

output "agent_gateway_subnet_id" {
  description = "ID of the Agent Gateway dedicated subnet"
  value       = var.enable_agent_gateway ? google_compute_subnetwork.agent_gateway[0].id : null
}

output "agent_gateway_subnet_self_link" {
  description = "Self link of the Agent Gateway dedicated subnet"
  value       = var.enable_agent_gateway ? google_compute_subnetwork.agent_gateway[0].self_link : null
}

output "agent_gateway_subnet_cidr" {
  description = "CIDR range of the Agent Gateway dedicated subnet"
  value       = var.enable_agent_gateway ? google_compute_subnetwork.agent_gateway[0].ip_cidr_range : null
}
