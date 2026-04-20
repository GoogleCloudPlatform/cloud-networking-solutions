# GKE Cluster Module

This module creates a GKE Standard cluster with GPU auto-provisioning, Workload Identity, and Gateway API support. It is designed for high-performance AI inference workloads and supports multiple cluster deployments via Terraform's `for_each` pattern.

## Features

- **GPU Auto-Provisioning:** Automatically manage node pools for H100, H200, A100, L4, and T4 accelerators.
- **Workload Identity:** Securely authenticate your pods using Google Service Accounts.
- **Gateway API Support:** Enable advanced traffic management and ingress using the Kubernetes Gateway API.
- **Observability:** Integrate with Cloud Logging, Cloud Monitoring, and Managed Prometheus by default.
- **Network Security:** Deploy private nodes with Cloud NAT for secure outbound internet access.

---

## Architecture

1.  **Control Plane:** Manages cluster operations and hosts the Gateway API controller and Workload Identity services.
2.  **Auto-Provisioned Node Pools:** GKE dynamically creates and scales GPU-equipped nodes based on your workload requirements.
3.  **Observability Stack:** System and workload metrics are automatically collected and sent to Google Cloud's monitoring services.

---

## Usage Guide

### Deploying a Single Cluster

```hcl
module "gke_cluster" {
  source = "./modules/gke-cluster"

  project_id           = "YOUR_PROJECT_ID"
  name                 = "inference-cluster"
  region               = "YOUR_REGION"
  network_self_link    = module.networking.network_self_link
  subnetwork_self_link = module.networking.subnet_self_link
  node_zones           = ["YOUR_REGION-a", "YOUR_REGION-b"]

  dns_domain          = "inference.example.com"
  deletion_protection = false
}
```

---

## Variables

### Required
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | The Google Cloud project ID. | `string` | - | Yes |
| `name` | The name for the GKE cluster. | `string` | - | Yes |
| `region` | The region where the cluster will be deployed. | `string` | - | Yes |
| `network_self_link` | The self-link of the VPC network. | `string` | - | Yes |
| `subnetwork_self_link` | The self-link of the VPC subnetwork. | `string` | - | Yes |
| `node_zones` | A list of zones for cluster nodes. | `list(string)` | - | Yes |

### Cluster Features
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `dns_domain` | DNS domain for the cluster. Set to null to disable cluster DNS. | `string` | `null` | No |
| `deletion_protection` | Enable deletion protection for the cluster. | `bool` | `false` | No |
| `enable_gateway_api` | Set to `true` to enable the Gateway API. | `bool` | `true` | No |
| `enable_workload_identity` | Enable Workload Identity. | `bool` | `true` | No |
| `enable_dataplane_v2` | Enable Dataplane V2 (eBPF). | `bool` | `true` | No |
| `enable_image_streaming` | Enable image streaming. | `bool` | `true` | No |
| `enable_shielded_nodes` | Enable shielded nodes. | `bool` | `true` | No |
| `enable_secret_manager` | Enable Secret Manager integration. | `bool` | `true` | No |
| `release_channel` | GKE release channel (`RAPID`, `REGULAR`, `STABLE`, or null). | `string` | `"RAPID"` | No |
| `private_nodes` | Enable private nodes. | `bool` | `true` | No |
| `node_service_account` | Service account email for GKE nodes. | `string` | `null` | No |
| `secret_sync_config` | Configuration for GKE Managed Secret Sync. | `object` | `null` | No |

### Auto-Provisioning
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `enable_cluster_autoscaling` | Enable cluster autoscaling (node auto-provisioning). | `bool` | `true` | No |
| `cluster_autoscaling` | Cluster autoscaling configuration (node auto-provisioning). | `object` | See defaults | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `name` | The name of the GKE cluster. |
| `id` | The unique ID of the GKE cluster. |
| `endpoint` | The IP address of the cluster's control plane. |
| `workload_identity_pool` | The Workload Identity pool for the cluster. |

---

## GPU Auto-Provisioning

The module configures auto-provisioning for a variety of NVIDIA GPUs. GKE will automatically create the appropriate node pool when it detects a pod requesting one of these resources.

The `resource_type` values used in `cluster_autoscaling.accelerator_resources` correspond to GCE accelerator types:

| GPU | Resource Type | Notes |
|-----|--------------|-------|
| NVIDIA H100 80GB | `nvidia-h100-80gb` | Standard H100 |
| NVIDIA H100 Mega 80GB | `nvidia-h100-mega-80gb` | H100 Mega variant |
| NVIDIA H200 141GB | `nvidia-h200-141gb` | Next-gen H200 |
| NVIDIA A100 80GB | `nvidia-a100-80gb` | A100 80GB variant |
| NVIDIA A100 40GB | `nvidia-tesla-a100` | A100 40GB (legacy naming with `tesla` prefix) |
| NVIDIA L4 | `nvidia-l4` | Inference-optimized |
| NVIDIA T4 | `nvidia-tesla-t4` | Budget inference (legacy naming with `tesla` prefix) |
| NVIDIA B200 | `nvidia-b200` | Blackwell architecture |

Note: Some GPU types use a legacy `nvidia-tesla-` prefix (A100 40GB, T4) while newer GPUs use the direct `nvidia-` prefix. Both naming styles are valid GCE accelerator type identifiers.

---

## Troubleshooting

- **GPU Quota:** If node pools fail to scale, verify that your project has sufficient GPU quota in the target region.
- **VPC Access:** Ensure your private nodes can reach the internet via Cloud NAT to download container images.
- **Gateway API:** Confirm that you are using a supported GatewayClass (e.g., `gke-l7-rilb`) for your ingress resources.

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
