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



variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for all Secure Web Proxy resources"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "network_self_link" {
  description = "Self-link of the VPC network the SWP gateway is attached to"
  type        = string
}

variable "swp_proxy_subnet_cidr" {
  description = "CIDR for the dedicated proxy-only subnet (purpose = REGIONAL_MANAGED_PROXY, role = ACTIVE). Must be a /24 or larger in RFC1918 space."
  type        = string
  default     = "10.30.0.0/24"
}

variable "agent_gateway_subnet_cidr" {
  description = "CIDR of the Agent Gateway PSC-I subnet. Traffic sourcing from this range is force-steered through the SWP via a policy-based route."
  type        = string
}

variable "private_subnet_id" {
  description = "ID (projects/P/regions/R/subnetworks/N) of a PRIVATE-purpose subnet from which the SWP gateway allocates its internal next-hop IP. Must be in the same VPC and region as the gateway. The REGIONAL_MANAGED_PROXY subnet is a separate regional prerequisite and must NOT be used here."
  type        = string
}
