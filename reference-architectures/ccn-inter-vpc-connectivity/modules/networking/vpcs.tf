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
  on_prem_subnets = concat(
    var.on_prem_base_subnets,
    var.enable_on_prem_cgn ? var.on_prem_cgn_subnets : [],
    var.enable_on_prem_pupi ? var.on_prem_pupi_subnets : []
  )

  prod_app1_subnets = concat(
    var.prod_app1_base_subnets,
    var.enable_prod_app1_cgn ? var.prod_app1_cgn_subnets : [],
    var.enable_prod_app1_pupi ? var.prod_app1_pupi_subnets : []
  )

  prod_app2_subnets = concat(
    var.prod_app2_base_subnets,
    var.enable_prod_app2_cgn ? var.prod_app2_cgn_subnets : [],
    var.enable_prod_app2_pupi ? var.prod_app2_pupi_subnets : []
  )

  vpcs = {
    on_prem = {
      project_id                        = local.on_prem_project_id
      network_name                      = "vpc-on-prem"
      description                       = "On Prem VPC"
      subnets                           = local.on_prem_subnets
      firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    }
    prod_transit = {
      project_id                        = local.prod_transit_project_id
      network_name                      = "vpc-p-transit"
      description                       = "Prod Transit VPC"
      subnets                           = var.prod_transit_vpc_subnets
      firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    }
    prod_services = {
      project_id                        = local.prod_host_project_id
      network_name                      = "vpc-p-services"
      description                       = "Prod Service VPC"
      subnets                           = var.prod_services_vpc_subnets
      firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    }
    prod_app1 = {
      project_id                        = local.prod_host_project_id
      network_name                      = "vpc-p-svpc-app-01"
      description                       = "Prod App1 VPC"
      subnets                           = local.prod_app1_subnets
      firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    }
    prod_app2 = {
      project_id                        = local.prod_host_project_id
      network_name                      = "vpc-p-svpc-app-02"
      description                       = "Prod App2 VPC"
      subnets                           = local.prod_app2_subnets
      firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    }
    prod_app3 = {
      project_id                        = local.prod_host_project_id
      network_name                      = "vpc-p-svpc-app-03"
      description                       = "Prod App3 VPC"
      subnets                           = var.prod_app3_base_subnets
      firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    }
  }

  vpc_subnets = {
    for k, v in local.vpcs : k => v
    if length(v.subnets) > 0
  }
}

# ------------------
# VPC Networks
# ------------------

module "vpcs" {
  source   = "terraform-google-modules/network/google//modules/vpc"
  version  = "~> 18.0"
  for_each = local.vpcs

  project_id                                = each.value.project_id
  network_name                              = each.value.network_name
  routing_mode                              = "GLOBAL"
  mtu                                       = var.vpc_mtu
  auto_create_subnetworks                   = false
  description                               = each.value.description
  network_firewall_policy_enforcement_order = each.value.firewall_policy_enforcement_order
}

# ------------------
# Subnets
# ------------------

module "subnets" {
  source   = "terraform-google-modules/network/google//modules/subnets-beta"
  version  = "~> 18.0"
  for_each = local.vpc_subnets

  project_id   = each.value.project_id
  network_name = module.vpcs[each.key].network_name
  subnets = [
    for s in each.value.subnets : merge(s, {
      # Enable Private Google Access on all standard subnets;
      # REGIONAL_MANAGED_PROXY and PRIVATE_SERVICE_CONNECT subnets do not support PGA in GCP.
      subnet_private_access = lookup(s, "purpose", null) == null ? "true" : "false"
    })
  ]
}
