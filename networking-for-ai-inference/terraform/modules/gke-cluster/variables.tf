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

# Required variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name" {
  description = "GKE cluster name"
  type        = string
}

variable "region" {
  description = "The GCP region for the cluster"
  type        = string
}

variable "network_self_link" {
  description = "VPC network self link"
  type        = string
}

variable "subnetwork_self_link" {
  description = "VPC subnetwork self link"
  type        = string
}

variable "node_zones" {
  description = "List of zones for cluster nodes"
  type        = list(string)
}

# Network configuration
variable "pods_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary range for services"
  type        = string
  default     = "services"
}

variable "max_pods_per_node" {
  description = "Maximum number of pods per node"
  type        = number
  default     = 110
}

# DNS configuration
variable "dns_domain" {
  description = "DNS domain for the cluster (e.g., 'cluster-name.region.example.com'). Set to null to disable cluster DNS."
  type        = string
  default     = null
}

# Cluster features
variable "deletion_protection" {
  description = "Enable deletion protection for the cluster"
  type        = bool
  default     = false
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
  default     = true
}

variable "enable_dataplane_v2" {
  description = "Enable Dataplane V2 (eBPF)"
  type        = bool
  default     = true
}

variable "enable_image_streaming" {
  description = "Enable image streaming"
  type        = bool
  default     = true
}

variable "enable_shielded_nodes" {
  description = "Enable shielded nodes"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable binary authorization"
  type        = bool
  default     = false
}

variable "enable_secret_manager" {
  description = "Enable Secret Manager integration"
  type        = bool
  default     = true
}

variable "enable_gateway_api" {
  description = "Enable Gateway API"
  type        = bool
  default     = true
}

# Access configuration
variable "private_nodes" {
  description = "Enable private nodes"
  type        = bool
  default     = true
}

variable "enable_dns_access" {
  description = "Enable DNS access for private clusters"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "Authorized networks for API server access. Maps to access_config.ip_access in the CFF gke-cluster-standard module."
  type = object({
    authorized_ranges                              = optional(map(string))
    disable_public_endpoint                        = optional(bool)
    gcp_public_cidrs_access_enabled                = optional(bool)
    private_endpoint_authorized_ranges_enforcement = optional(bool)
    private_endpoint_config = optional(object({
      endpoint_subnetwork = optional(string)
      global_access       = optional(bool, true)
    }))
  })
  default = null
}

# Logging configuration
variable "enable_system_logs" {
  description = "Enable system logs"
  type        = bool
  default     = true
}

variable "enable_workloads_logs" {
  description = "Enable workload logs"
  type        = bool
  default     = true
}

variable "enable_api_server_logs" {
  description = "Enable API server logs"
  type        = bool
  default     = true
}

variable "enable_scheduler_logs" {
  description = "Enable scheduler logs"
  type        = bool
  default     = true
}

variable "enable_controller_logs" {
  description = "Enable controller logs"
  type        = bool
  default     = true
}

# Monitoring configuration
variable "enable_system_metrics" {
  description = "Enable system metrics"
  type        = bool
  default     = true
}

variable "managed_prometheus" {
  description = "Managed Prometheus configuration"
  type = object({
    enabled = bool
  })
  default = {
    enabled = true
  }
}

variable "enable_api_server_metrics" {
  description = "Enable API server metrics"
  type        = bool
  default     = true
}

variable "enable_controller_metrics" {
  description = "Enable controller metrics"
  type        = bool
  default     = true
}

variable "enable_scheduler_metrics" {
  description = "Enable scheduler metrics"
  type        = bool
  default     = true
}

variable "enable_daemonset_metrics" {
  description = "Enable daemonset metrics"
  type        = bool
  default     = true
}

variable "enable_deployment_metrics" {
  description = "Enable deployment metrics"
  type        = bool
  default     = true
}

variable "enable_hpa_metrics" {
  description = "Enable HPA metrics"
  type        = bool
  default     = true
}

variable "enable_pod_metrics" {
  description = "Enable pod metrics"
  type        = bool
  default     = true
}

variable "enable_statefulset_metrics" {
  description = "Enable statefulset metrics"
  type        = bool
  default     = true
}

variable "enable_storage_metrics" {
  description = "Enable storage metrics"
  type        = bool
  default     = true
}

variable "enable_node_metrics" {
  description = "Enable node metrics"
  type        = bool
  default     = true
}

# Maintenance configuration
variable "maintenance_config" {
  description = "Cluster maintenance configuration"
  type = object({
    daily_window_start_time = string
    recurring_window = optional(object({
      recurrence = string
      start_time = string
      end_time   = string
    }))
    maintenance_exclusions = optional(list(object({
      name       = string
      start_time = string
      end_time   = string
      scope      = optional(string)
    })))
  })
  default = {
    daily_window_start_time = "03:00"
    recurring_window        = null
    maintenance_exclusions  = []
  }
}

# Release channel
variable "release_channel" {
  description = "GKE release channel (RAPID, REGULAR, STABLE, or null for static version)"
  type        = string
  default     = "RAPID"
}

# Addons
variable "enable_addons" {
  description = "GKE addons configuration"
  type = object({
    dns_cache                      = bool
    gce_persistent_disk_csi_driver = bool
    horizontal_pod_autoscaling     = bool
    http_load_balancing            = bool
    image_streaming                = bool
    config_connector               = bool
    gcp_filestore_csi_driver       = optional(bool, false)
    gcs_fuse_csi_driver            = optional(bool, false)
    gke_backup_agent               = optional(bool, false)
    network_policy                 = optional(bool, false)
    stateful_ha                    = optional(bool, false)
  })
  default = {
    dns_cache                      = true
    gce_persistent_disk_csi_driver = true
    horizontal_pod_autoscaling     = true
    http_load_balancing            = true
    image_streaming                = true
    config_connector               = true
    gcp_filestore_csi_driver       = false
    gcs_fuse_csi_driver            = false
    gke_backup_agent               = false
    network_policy                 = false
    stateful_ha                    = false
  }
}

# Node configuration (maps to CFF gke-cluster-standard node_config)
variable "node_config" {
  description = "Default node configuration for the cluster."
  type = object({
    boot_disk_kms_key             = optional(string)
    k8s_labels                    = optional(map(string))
    labels                        = optional(map(string))
    service_account               = optional(string)
    oauth_scopes                  = optional(list(string), ["https://www.googleapis.com/auth/cloud-platform"])
    tags                          = optional(list(string))
    workload_metadata_config_mode = optional(string, "GKE_METADATA")
    kubelet_readonly_port_enabled = optional(bool, true)
  })
  default = {}
}

# Cluster autoscaling
variable "enable_cluster_autoscaling" {
  description = "Enable cluster autoscaling (node auto-provisioning)"
  type        = bool
  default     = true
}

variable "cluster_autoscaling" {
  description = "Cluster autoscaling configuration (node auto-provisioning). Maps to CFF gke-cluster-standard cluster_autoscaling."
  type = object({
    enabled             = optional(bool, true)
    autoscaling_profile = optional(string, "OPTIMIZE_UTILIZATION")
    auto_provisioning_defaults = optional(object({
      boot_disk_kms_key = optional(string)
      disk_size         = optional(number, 100)
      disk_type         = optional(string, "pd-balanced")
      image_type        = optional(string)
      oauth_scopes      = optional(list(string))
      service_account   = optional(string)
      management = optional(object({
        auto_repair  = optional(bool, true)
        auto_upgrade = optional(bool, true)
      }))
      shielded_instance_config = optional(object({
        integrity_monitoring = optional(bool, true)
        secure_boot          = optional(bool, false)
      }))
      upgrade_settings = optional(object({
        blue_green = optional(object({
          node_pool_soak_duration = optional(string)
          standard_rollout_policy = optional(object({
            batch_percentage    = optional(number)
            batch_node_count    = optional(number)
            batch_soak_duration = optional(string)
          }))
        }))
        surge = optional(object({
          max         = optional(number)
          unavailable = optional(number)
        }))
      }))
    }))
    auto_provisioning_locations = optional(list(string))
    cpu_limits = optional(object({
      min = optional(number, 0)
      max = number
    }))
    mem_limits = optional(object({
      min = optional(number, 0)
      max = number
    }))
    accelerator_resources = optional(list(object({
      resource_type = string
      min           = optional(number, 0)
      max           = number
    })))
  })
  default = {
    enabled             = true
    autoscaling_profile = "OPTIMIZE_UTILIZATION"
    auto_provisioning_defaults = {
      disk_size    = 100
      disk_type    = "pd-balanced"
      oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
      management = {
        auto_repair  = false
        auto_upgrade = true
      }
      shielded_instance_config = {
        secure_boot          = false
        integrity_monitoring = true
      }
      upgrade_settings = {
        surge = {
          max         = 2
          unavailable = 0
        }
      }
    }
    cpu_limits = {
      max = 10000
    }
    mem_limits = {
      max = 80000
    }
    accelerator_resources = [
      { resource_type = "nvidia-h100-80gb", max = 10 },
      { resource_type = "nvidia-h100-mega-80gb", max = 10 },
      { resource_type = "nvidia-a100-80gb", max = 10 },
      { resource_type = "nvidia-tesla-a100", max = 10 },
      { resource_type = "nvidia-l4", max = 10 },
      { resource_type = "nvidia-tesla-t4", max = 10 },
      { resource_type = "nvidia-b200", max = 10 },
      { resource_type = "nvidia-h200-141gb", max = 10 },
    ]
  }
}

# Default nodepool
variable "default_nodepool" {
  description = "Default node pool configuration. Set to null to remove the default node pool."
  type = object({
    remove_pool        = optional(bool, true)
    initial_node_count = optional(number, 1)
  })
  default = null
}

# Node service account
variable "node_service_account" {
  description = "Service account email for GKE nodes. If null, uses default Compute Engine service account."
  type        = string
  default     = null
}

variable "secret_sync_config" {
  description = "Secret sync configuration for syncing secrets from Secret Manager to the cluster. Requires secret_manager_config to be enabled."
  type = object({
    enabled = bool
    rotation_config = optional(object({
      enabled           = optional(bool)
      rotation_interval = optional(string)
    }))
  })
  default = null
}
