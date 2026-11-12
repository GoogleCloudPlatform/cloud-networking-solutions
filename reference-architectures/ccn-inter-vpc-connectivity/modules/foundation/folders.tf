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

# Create the level 1 folder: ${var.prefix}-network-lab
module "base_folder" {
  source  = "terraform-google-modules/folders/google"
  version = "~> 5.1"

  parent = "organizations/${var.organization_id}"
  names = [
    "fldr-${var.prefix}-network-lab",
  ]
  deletion_protection = var.deletion_protection
}

# Create the level 2 folders: ${var.prefix}-on-prem, ${var.prefix}-production, and ${var.prefix}-development
module "level2_folders" {
  source  = "terraform-google-modules/folders/google"
  version = "~> 5.1"

  parent = module.base_folder.id
  names = [
    "fldr-${var.prefix}-on-prem",
    "fldr-${var.prefix}-production",
    "fldr-${var.prefix}-development",
  ]
  deletion_protection = var.deletion_protection
}

# Create the level 3 folders for the production environment
module "prod_level3_folders" {
  source  = "terraform-google-modules/folders/google"
  version = "~> 5.1"

  parent = module.level2_folders.ids["fldr-${var.prefix}-production"]
  names = [
    "fldr-${var.prefix}-p-application",
    "fldr-${var.prefix}-p-shared-infra",
  ]
  deletion_protection = var.deletion_protection
}

# Create the level 3 folders for the development environment
module "dev_level3_folders" {
  source  = "terraform-google-modules/folders/google"
  version = "~> 5.1"

  parent = module.level2_folders.ids["fldr-${var.prefix}-development"]
  names = [
    "fldr-${var.prefix}-d-application",
    "fldr-${var.prefix}-d-shared-infra",
  ]
  deletion_protection = var.deletion_protection
}

# Reset org policy constraints/compute.restrictVpnPeerIPs
# Note: google_org_policy_policy fails when deploying with personal ADC credentials
# (requires Service Account impersonation or user_project_override).
# Run the gcloud command emitted by the `org_policy_reset_command` output instead.
/*
resource "google_org_policy_policy" "reset_compute_restrictVpnPeerIPs" {
  name   = "${module.base_folder.id}/policies/compute.restrictVpnPeerIPs"
  parent = module.base_folder.id

  spec {
    reset = true
  }
}
*/
