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

# Create Production and Development projects

locals {
  core_projects = {
    on_prem = {
      name                           = "prj-${var.prefix}-on-prem"
      folder_id                      = module.level2_folders.ids["fldr-${var.prefix}-on-prem"]
      enable_shared_vpc_host_project = false
      environment                    = "on-prem"
    }
    prod_host = {
      name                           = "prj-${var.prefix}-p-net-host"
      folder_id                      = module.prod_level3_folders.ids["fldr-${var.prefix}-p-shared-infra"]
      enable_shared_vpc_host_project = true
      environment                    = "prod-host"
    }
    prod_transit = {
      name                           = "prj-${var.prefix}-p-net-transit"
      folder_id                      = module.prod_level3_folders.ids["fldr-${var.prefix}-p-shared-infra"]
      enable_shared_vpc_host_project = false
      environment                    = "prod-transit"
    }
    dev_host = {
      name                           = "prj-${var.prefix}-d-net-host"
      folder_id                      = module.dev_level3_folders.ids["fldr-${var.prefix}-d-shared-infra"]
      enable_shared_vpc_host_project = true
      environment                    = "dev-host"
    }
    dev_transit = {
      name                           = "prj-${var.prefix}-d-net-transit"
      folder_id                      = module.dev_level3_folders.ids["fldr-${var.prefix}-d-shared-infra"]
      enable_shared_vpc_host_project = false
      environment                    = "dev-transit"
    }
  }
}

module "projects" {
  source   = "terraform-google-modules/project-factory/google"
  version  = "~> 18.1"
  for_each = local.core_projects

  name                           = each.value.name
  random_project_id              = true
  org_id                         = var.organization_id
  folder_id                      = each.value.folder_id
  billing_account                = var.billing_account_id
  enable_shared_vpc_host_project = each.value.enable_shared_vpc_host_project
  deletion_policy                = local.project_deletion_policy
  activate_apis                  = local.default_apis

  labels = merge(local.labels, { environment = each.value.environment })

  disable_dependent_services  = false
  disable_services_on_destroy = false
}
