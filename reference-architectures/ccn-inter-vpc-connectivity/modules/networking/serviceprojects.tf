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
  app_project_ids = toset(["prj-${var.prefix}-p-svc-app-01", "prj-${var.prefix}-p-svc-app-02"])
}

# Production Service Projects
module "prod_service_projects" {
  source               = "terraform-google-modules/project-factory/google"
  version              = "~> 18.1"
  for_each             = local.app_project_ids
  name                 = each.key
  random_project_id    = true
  org_id               = var.organization_id
  folder_id            = local.prod_application_folder_id
  billing_account      = var.billing_account_id
  svpc_host_project_id = local.prod_host_project_id
  deletion_policy      = var.deletion_protection ? "PREVENT" : "DELETE"
  grant_network_role   = false
  activate_apis = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
    "dns.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]

  labels = merge(local.labels, { environment = "prod-svc-app" })

  disable_dependent_services  = false
  disable_services_on_destroy = false
}
