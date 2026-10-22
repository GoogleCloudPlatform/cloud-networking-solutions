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



output "gateway_id" {
  description = "Full resource ID of the Secure Web Proxy gateway"
  value       = google_network_services_gateway.swp.id
}

output "gateway_internal_ip" {
  description = "Internal IP address auto-assigned to the SWP gateway from the proxy-only subnet. This is the next-hop IP used by the policy-based route."
  value       = google_network_services_gateway.swp.addresses[0]
}

output "proxy_subnet_id" {
  description = "ID of the SWP proxy-only subnet"
  value       = google_compute_subnetwork.swp_proxy.id
}

output "proxy_subnet_self_link" {
  description = "Self-link of the SWP proxy-only subnet"
  value       = google_compute_subnetwork.swp_proxy.self_link
}

output "proxy_subnet_cidr" {
  description = "CIDR of the SWP proxy-only subnet"
  value       = google_compute_subnetwork.swp_proxy.ip_cidr_range
}

output "security_policy_id" {
  description = "ID of the gateway security policy"
  value       = google_network_security_gateway_security_policy.swp.id
}
