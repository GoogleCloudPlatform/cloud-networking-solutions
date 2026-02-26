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
 * GKE Cluster Module
 *
 * Reusable module for creating a GKE cluster with GPU auto-provisioning.
 * Eliminates duplication by providing a single, parameterized cluster definition.
 */

module "gke" {
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-cluster-standard?ref=v53.0.0"
  project_id          = var.project_id
  name                = var.name
  location            = var.region
  deletion_protection = var.deletion_protection

  vpc_config = {
    network    = var.network_self_link
    subnetwork = var.subnetwork_self_link
    secondary_range_names = {
      pods     = var.pods_range_name
      services = var.services_range_name
    }
  }

  max_pods_per_node = var.max_pods_per_node

  # Node locations
  node_locations = var.node_zones

  # Enable features
  enable_features = {
    workload_identity     = var.enable_workload_identity
    dataplane_v2          = var.enable_dataplane_v2
    image_streaming       = var.enable_image_streaming
    shielded_nodes        = var.enable_shielded_nodes
    binary_authorization  = var.enable_binary_authorization
    secret_manager_config = var.enable_secret_manager
    secret_sync_config    = var.secret_sync_config
    gateway_api           = var.enable_gateway_api
    dns = var.dns_domain != null ? {
      provider                      = "CLOUD_DNS"
      scope                         = "CLUSTER_SCOPE"
      additive_vpc_scope_dns_domain = var.dns_domain
    } : null
  }

  # Access configuration
  access_config = {
    dns_access    = var.enable_dns_access
    ip_access     = var.authorized_networks
    private_nodes = var.private_nodes
  }

  # Monitoring and logging
  logging_config = {
    enable_system_logs     = var.enable_system_logs
    enable_workloads_logs  = var.enable_workloads_logs
    enable_api_server_logs = var.enable_api_server_logs
    enable_scheduler_logs  = var.enable_scheduler_logs
    enable_controller_logs = var.enable_controller_logs
  }

  monitoring_config = {
    enable_system_metrics      = var.enable_system_metrics
    managed_prometheus         = var.managed_prometheus
    enable_api_server_metrics  = var.enable_api_server_metrics
    enable_controller_metrics  = var.enable_controller_metrics
    enable_scheduler_metrics   = var.enable_scheduler_metrics
    enable_daemonset_metrics   = var.enable_daemonset_metrics
    enable_deployment_metrics  = var.enable_deployment_metrics
    enable_hpa_metrics         = var.enable_hpa_metrics
    enable_pod_metrics         = var.enable_pod_metrics
    enable_statefulset_metrics = var.enable_statefulset_metrics
    enable_storage_metrics     = var.enable_storage_metrics
    enable_node_metrics        = var.enable_node_metrics
  }

  # Maintenance policy
  maintenance_config = var.maintenance_config

  # Release channel
  release_channel = var.release_channel

  # Addons
  enable_addons = var.enable_addons

  # Node configuration with optional service account override
  node_config = var.node_service_account != null ? merge(
    var.node_config,
    {
      service_account = var.node_service_account
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  ) : var.node_config

  # Node auto-provisioning configuration with optional service account override
  cluster_autoscaling = var.enable_cluster_autoscaling ? {
    enabled             = var.cluster_autoscaling.enabled
    autoscaling_profile = var.cluster_autoscaling.autoscaling_profile
    auto_provisioning_defaults = var.node_service_account != null ? merge(
      var.cluster_autoscaling.auto_provisioning_defaults,
      {
        service_account = var.node_service_account
        oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
      }
    ) : var.cluster_autoscaling.auto_provisioning_defaults
    cpu_limits            = var.cluster_autoscaling.cpu_limits
    mem_limits            = var.cluster_autoscaling.mem_limits
    accelerator_resources = var.cluster_autoscaling.accelerator_resources
  } : null

  # Default node pool configuration
  default_nodepool = var.default_nodepool
}
