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
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the primary subnet"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "primary_subnet_cidr" {
  description = "CIDR range for the primary subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "enable_agent_gateway" {
  description = "Provision the dedicated subnet that hosts the Agent Gateway PSC-Interface network attachment."
  type        = bool
  default     = false
}

variable "agent_gateway_subnet_cidr" {
  description = "CIDR for the Agent Gateway dedicated subnet. Must be within RFC1918, min /26 (a /28 risks PSC subnet exhaustion — known-issues.md #19). If inside 10.0.0.0/8, must not overlap 10.0.0.0/24, 10.0.1.0/24, or 10.0.2.0/24 (Agent Gateway egress restrictions)."
  type        = string
  default     = "10.20.0.0/26"
  validation {
    condition = (
      cidrnetmask(var.agent_gateway_subnet_cidr) != null &&
      tonumber(split("/", var.agent_gateway_subnet_cidr)[1]) <= 26 &&
      tonumber(split("/", var.agent_gateway_subnet_cidr)[1]) >= 8
    )
    error_message = "agent_gateway_subnet_cidr must be a valid CIDR with prefix length between /8 and /26."
  }
  validation {
    condition = (
      startswith(var.agent_gateway_subnet_cidr, "10.") ||
      startswith(var.agent_gateway_subnet_cidr, "172.") ||
      startswith(var.agent_gateway_subnet_cidr, "192.168.")
    )
    error_message = "agent_gateway_subnet_cidr must fall within RFC1918 (10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16)."
  }
  validation {
    condition = !(
      startswith(var.agent_gateway_subnet_cidr, "10.0.0.") ||
      startswith(var.agent_gateway_subnet_cidr, "10.0.1.") ||
      startswith(var.agent_gateway_subnet_cidr, "10.0.2.")
    )
    error_message = "agent_gateway_subnet_cidr must not overlap 10.0.0.0/24, 10.0.1.0/24, or 10.0.2.0/24 — Agent Gateway cannot egress to those ranges."
  }
}
