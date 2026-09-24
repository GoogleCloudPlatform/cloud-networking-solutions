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
  description = "GCP project ID hosting the Agent Gateway"
  type        = string
}

variable "project_number" {
  description = "GCP project number hosting the Agent Gateway"
  type        = string
}

variable "region" {
  description = "Region for the Agent Gateway and PSC-I network attachment"
  type        = string
}

variable "name" {
  description = "Name of the Agent Gateway resource. Also used as prefix for the network attachment and firewall rule."
  type        = string
  default     = "agent-gateway"
}

variable "network_self_link" {
  description = "Self link of the VPC network where the PSC-I network attachment lives"
  type        = string
}

variable "agent_gateway_subnet_self_link" {
  description = "Self link of the dedicated subnet that hosts the Agent Gateway PSC-I network attachment"
  type        = string
}

variable "agent_gateway_subnet_cidr" {
  description = "CIDR of the dedicated subnet — used to scope the inbound firewall rule"
  type        = string
}
