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
  labels = {
    purpose = "network-lab"
    created = "terraform"
  }

  base_folder_id             = data.google_active_folder.fldr_base.id
  prod_folder_id             = data.google_active_folder.fldr_prod.id
  prod_application_folder_id = data.google_active_folder.fldr_p_application.id


  prod_host_project_id    = data.google_projects.prod_host_project.projects[0].project_id
  prod_transit_project_id = data.google_projects.prod_transit_project.projects[0].project_id
  on_prem_project_id      = data.google_projects.on_prem_project.projects[0].project_id
}

# Level 1 folder
data "google_active_folder" "fldr_base" {
  display_name = "fldr-${var.prefix}-network-lab"
  parent       = "organizations/${var.organization_id}"
}

# Level 2 folders
data "google_active_folder" "fldr_prod" {
  display_name = "fldr-${var.prefix}-production"
  parent       = local.base_folder_id
}

# data "google_active_folder" "fldr_dev" {
#   display_name = "fldr-${var.prefix}-development"
#   parent       = local.base_folder_id
# }

data "google_active_folder" "fldr_onprem" {
  display_name = "fldr-${var.prefix}-on-prem"
  parent       = local.base_folder_id
}

# Level 3 folders
data "google_active_folder" "fldr_p_application" {
  display_name = "fldr-${var.prefix}-p-application"
  parent       = local.prod_folder_id
}

data "google_active_folder" "fldr_p_shared_infra" {
  display_name = "fldr-${var.prefix}-p-shared-infra"
  parent       = local.prod_folder_id
}

#Projects
data "google_projects" "prod_host_project" {
  filter = "parent.id:${split("/", data.google_active_folder.fldr_p_shared_infra.name)[1]} labels.environment=prod-host lifecycleState=ACTIVE"
}

data "google_projects" "prod_transit_project" {
  filter = "parent.id:${split("/", data.google_active_folder.fldr_p_shared_infra.name)[1]} labels.environment=prod-transit lifecycleState=ACTIVE"
}

data "google_projects" "on_prem_project" {
  filter = "parent.id:${split("/", data.google_active_folder.fldr_onprem.name)[1]} labels.environment=on-prem lifecycleState=ACTIVE"
}
