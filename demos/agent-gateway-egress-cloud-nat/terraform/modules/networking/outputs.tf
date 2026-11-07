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



# VPC Outputs
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

output "subnets" {
  description = "All subnets"
  value       = module.vpc.subnets
}

output "subnet_self_links" {
  description = "Map of subnet self links"
  value       = module.vpc.subnet_self_links
}

# NAT Outputs
output "nat_router_name" {
  description = "Cloud Router name"
  value       = google_compute_router.nat_router.name
}

output "nat_gateway_name" {
  description = "Cloud NAT gateway name"
  value       = google_compute_router_nat.nat_gateway.name
}

output "nat_static_ip" {
  description = "Reserved static external IP address used by Cloud NAT. All Agent Runtime egress exits from this address — this is what the public MCP server sees."
  value       = google_compute_address.static_address.address
}

output "nat_static_ip_self_link" {
  description = "Self-link of the reserved NAT static IP address"
  value       = google_compute_address.static_address.self_link
}

# Available zones in the region
output "available_zones" {
  description = "List of available zones in the region"
  value       = data.google_compute_zones.available.names
}

# Proxy-only subnet for internal load balancers
output "proxy_subnet_id" {
  description = "ID of the proxy-only subnet for internal load balancers"
  value       = module.vpc.subnets_proxy_only != null ? try(values(module.vpc.subnets_proxy_only)[0].id, null) : null
}

output "proxy_subnet_name" {
  description = "Name of the proxy-only subnet"
  value       = "${var.name_prefix}-proxy-subnet"
}

# PSC subnet for Private Service Connect
output "psc_subnet_id" {
  description = "ID of the Private Service Connect subnet"
  value       = try(values(module.vpc.subnets_psc)[0].id, null)
}

output "psc_subnet_self_link" {
  description = "Self link of the Private Service Connect subnet"
  value       = try(values(module.vpc.subnets_psc)[0].self_link, null)
}

# PSC Interface Outputs

output "psc_interface_network_attachment_id" {
  description = "Full resource ID of the PSC Interface network attachment"
  value       = var.enable_psc_interface ? google_compute_network_attachment.psc_interface[0].id : null
}

output "psc_interface_network_attachment_name" {
  description = "Name of the PSC Interface network attachment"
  value       = var.enable_psc_interface ? google_compute_network_attachment.psc_interface[0].name : null
}

output "psc_interface_subnet_self_link" {
  description = "Self link of the PSC Interface subnet"
  value       = var.enable_psc_interface ? google_compute_subnetwork.psc_interface[0].self_link : null
}

# Agent Gateway dedicated subnet outputs

output "agent_gateway_subnet_id" {
  description = "ID of the Agent Gateway dedicated subnet"
  value       = google_compute_subnetwork.agent_gateway.id
}

output "agent_gateway_subnet_self_link" {
  description = "Self link of the Agent Gateway dedicated subnet"
  value       = google_compute_subnetwork.agent_gateway.self_link
}

output "agent_gateway_subnet_cidr" {
  description = "CIDR range of the Agent Gateway dedicated subnet"
  value       = google_compute_subnetwork.agent_gateway.ip_cidr_range
}