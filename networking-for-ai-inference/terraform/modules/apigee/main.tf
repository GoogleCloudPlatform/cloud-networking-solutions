/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Apigee Primitive Module
 *
 * A standalone, reusable module for Apigee organization management.
 * Creates Apigee organization, environments, environment groups, and instances.
 *
 * This module is designed to be used independently or composed by wrapper modules
 * like semantic-cache.
 *
 * Key features:
 * - Object-based configuration for clean variable structure
 * - Supports both VPC peering and Non-VPC Peering (PSC) modes
 * - Environment properties support for service extensions
 * - APIM Operator Workload Identity support
 * - DNS peering zone configuration
 */

locals {
  # Apigee service agent (per-project service account)
  # Format: service-{PROJECT_NUMBER}@gcp-sa-apigee.iam.gserviceaccount.com
  apigee_service_agent = "serviceAccount:service-${var.project_number}@gcp-sa-apigee.iam.gserviceaccount.com"

  # Apigee tenant project ID (e.g., "m62d5b515e41e50e6-tp")
  # This is the project Apigee uses for PSC connections, different from the main project
  apigee_tenant_project_id = try(module.apigee.organization.apigee_project_id, null)

  # Strip environments from instances to prevent the Fabric module from creating
  # instance attachments. We create them separately below with proper dependencies
  # on our own google_apigee_environment resources.
  instances_without_environments = {
    for k, v in var.instances : k => merge(v, { environments = [] })
  }

  # Build instance-to-environment attachment map from the original instances variable
  instance_environment_attachments = merge(flatten([
    for instance_key, instance in var.instances : [
      for env in coalesce(instance.environments, []) : {
        "${instance_key}-${env}" = {
          instance    = instance_key
          environment = env
        }
      }
    ]
  ])...)
}

# ==============================================================================
# APIGEE ORGANIZATION
# ==============================================================================

module "apigee" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/apigee?ref=v53.0.0"
  project_id = var.project_id

  organization = {
    display_name            = var.organization.display_name
    description             = var.organization.description
    billing_type            = var.organization.billing_type
    analytics_region        = coalesce(var.organization.analytics_region, var.region)
    authorized_network      = var.organization.disable_vpc_peering ? null : var.vpc_id
    runtime_type            = var.organization.runtime_type
    database_encryption_key = var.organization.database_encryption_key
    disable_vpc_peering     = var.organization.disable_vpc_peering
  }

  envgroups = var.envgroups

  # Environments created separately using google_apigee_environment to support properties
  environments = {}

  # Pass instances WITHOUT environments to prevent the Fabric module from creating
  # instance attachments. We create them separately with proper dependencies.
  instances = local.instances_without_environments

  endpoint_attachments = var.endpoint_attachments

  # DNS zones managed separately for dependency ordering
  dns_zones = {}
}

# ==============================================================================
# APIGEE ENVIRONMENTS
# ==============================================================================

# Create Apigee environments using google_apigee_environment directly
# This allows setting properties like apigee-service-extension-enabled
resource "google_apigee_environment" "environments" {
  for_each = var.environments

  org_id       = module.apigee.org_id
  name         = each.key
  display_name = each.value.display_name
  description  = each.value.description
  type         = each.value.type

  dynamic "node_config" {
    for_each = each.value.node_config != null ? [each.value.node_config] : []
    content {
      min_node_count = node_config.value.min_node_count
      max_node_count = node_config.value.max_node_count
    }
  }

  dynamic "properties" {
    for_each = each.value.properties != null ? [each.value.properties] : []
    content {
      dynamic "property" {
        for_each = properties.value
        content {
          name  = property.key
          value = property.value
        }
      }
    }
  }

  depends_on = [module.apigee]
}

# Create environment-to-envgroup attachments
resource "google_apigee_envgroup_attachment" "envgroup_attachments" {
  for_each = {
    for pair in flatten([
      for env_name, env in var.environments : [
        for envgroup in env.envgroups : {
          key      = "${env_name}-${envgroup}"
          env_name = env_name
          envgroup = envgroup
        }
      ]
    ]) : pair.key => pair
  }

  envgroup_id = module.apigee.envgroups[each.value.envgroup].id
  environment = google_apigee_environment.environments[each.value.env_name].name

  depends_on = [google_apigee_environment.environments]
}

# ==============================================================================
# INSTANCE ATTACHMENTS
# ==============================================================================

# Create instance-to-environment attachments separately from the Fabric module
# This ensures proper dependency ordering: environments must exist before attachments
resource "google_apigee_instance_attachment" "instance_attachments" {
  for_each = local.instance_environment_attachments

  instance_id = module.apigee.instances[each.value.instance].id
  environment = each.value.environment

  depends_on = [
    google_apigee_environment.environments,
    module.apigee
  ]
}
# ==============================================================================
# SERVICE ACCOUNTS
# ==============================================================================

# Service Account for Apigee proxy runtime operations
resource "google_service_account" "proxy_runtime" {
  count        = var.create_service_accounts ? 1 : 0
  project      = var.project_id
  account_id   = "${var.service_account_prefix}-proxy-runtime"
  display_name = "Apigee Proxy Runtime Service Account"
  description  = "Service account used for Apigee proxy runtime operations and deployments"
}

# Grant AI Platform User role to the proxy runtime service account
resource "google_project_iam_member" "proxy_runtime_aiplatform_user" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.proxy_runtime[0].email}"

  depends_on = [google_service_account.proxy_runtime]
}

# Grant Service Account User role to the proxy runtime service account
resource "google_project_iam_member" "proxy_runtime_sa_user" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.proxy_runtime[0].email}"

  depends_on = [google_service_account.proxy_runtime]
}

# ==============================================================================
# APIM OPERATOR SERVICE ACCOUNT (GSA-based Workload Identity)
# ==============================================================================
# The APIM Operator uses ComputeEngineCredentials which requires a traditional
# GSA-based Workload Identity setup. Direct principal:// grants are NOT supported.
# The KSA must be annotated with: iam.gke.io/gcp-service-account: [GSA-EMAIL]

# GCP Service Account for Apigee APIM Operator
resource "google_service_account" "apim_operator" {
  count        = var.create_apim_operator_iam ? 1 : 0
  project      = var.project_id
  account_id   = "${var.service_account_prefix}-apim-gsa"
  display_name = "Apigee APIM Operator GSA"
  description  = "GCP service account for Apigee APIM Operator - required for GSA-based Workload Identity"
}

# Workload Identity binding - allows Kubernetes SA to impersonate this GCP SA
# Uses serviceAccount: format (not principal://) for compatibility with ComputeEngineCredentials
resource "google_service_account_iam_member" "apim_workload_identity" {
  count              = var.create_apim_operator_iam && var.enable_apim_workload_identity ? 1 : 0
  service_account_id = google_service_account.apim_operator[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.apim_operator_namespace}/${var.apim_operator_ksa}]"

  depends_on = [google_service_account.apim_operator]
}

# Grant Apigee Admin role to the GSA
resource "google_project_iam_member" "apim_apigee_admin" {
  count   = var.create_apim_operator_iam ? 1 : 0
  project = var.project_id
  role    = "roles/apigee.admin"
  member  = "serviceAccount:${google_service_account.apim_operator[0].email}"

  depends_on = [google_service_account.apim_operator]
}

# Grant Network Services Extensions Admin role to the GSA
resource "google_project_iam_member" "apim_extensions_admin" {
  count   = var.create_apim_operator_iam ? 1 : 0
  project = var.project_id
  role    = "roles/networkservices.serviceExtensionsAdmin"
  member  = "serviceAccount:${google_service_account.apim_operator[0].email}"

  depends_on = [google_service_account.apim_operator]
}

# Grant Compute Network Admin role to the GSA
resource "google_project_iam_member" "apim_network_admin" {
  count   = var.create_apim_operator_iam ? 1 : 0
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.apim_operator[0].email}"

  depends_on = [google_service_account.apim_operator]
}

# Grant Compute Load Balancer Admin role to the GSA
resource "google_project_iam_member" "apim_lb_admin" {
  count   = var.create_apim_operator_iam ? 1 : 0
  project = var.project_id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.apim_operator[0].email}"

  depends_on = [google_service_account.apim_operator]
}
