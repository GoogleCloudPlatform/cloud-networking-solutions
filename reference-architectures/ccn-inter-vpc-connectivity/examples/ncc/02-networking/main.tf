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

module "networking" {
  source             = "../../../modules/networking/"
  organization_id    = var.organization_id
  billing_account_id = var.billing_account_id
  prefix             = var.prefix
  enable_ncc         = true

  # enable_on_prem_cgn        = var.enable_on_prem_cgn
  # enable_on_prem_pupi       = var.enable_on_prem_pupi
  # enable_prod_app1_cgn      = var.enable_prod_app1_cgn
  # enable_prod_app1_pupi     = var.enable_prod_app1_pupi
  # enable_prod_app2_cgn      = var.enable_prod_app2_cgn
  # enable_prod_app2_pupi     = var.enable_prod_app2_pupi
  # on_prem_base_subnets      = var.on_prem_base_subnets
  # on_prem_cgn_subnets       = var.on_prem_cgn_subnets
  # on_prem_pupi_subnets      = var.on_prem_pupi_subnets
  # prod_transit_vpc_subnets  = var.prod_transit_vpc_subnets
  # prod_services_vpc_subnets = var.prod_services_vpc_subnets
  # prod_app1_base_subnets    = var.prod_app1_base_subnets
  # prod_app1_cgn_subnets     = var.prod_app1_cgn_subnets
  # prod_app1_pupi_subnets    = var.prod_app1_pupi_subnets
  # prod_app2_base_subnets    = var.prod_app2_base_subnets
  # prod_app2_cgn_subnets     = var.prod_app2_cgn_subnets
  # prod_app2_pupi_subnets    = var.prod_app2_pupi_subnets
}
