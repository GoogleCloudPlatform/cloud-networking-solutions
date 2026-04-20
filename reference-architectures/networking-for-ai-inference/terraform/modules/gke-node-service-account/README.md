# GKE Node Service Account Module

This module creates a dedicated service account for GKE node pools with least-privilege IAM permissions. This replaces the default Compute Engine service account to improve your cluster's security posture.

## Overview

The GKE Node Service Account module provisions:

- A dedicated Google Service Account (GSA) for GKE nodes.
- Least-privilege IAM role bindings tailored for node operations.
- Integration with the GKE Container Engine robot service account.
- Optional Secret Manager access for the CSI driver.

---

## Usage Guide

### Basic Configuration
Include this module in your Terraform configuration and pass the resulting email to your GKE cluster module.

```hcl
module "gke_node_service_account" {
  source = "./modules/gke-node-service-account"

  project_id     = "YOUR_PROJECT_ID"
  project_number = "YOUR_PROJECT_NUMBER"

  service_account_name = "gke-inference-nodes"
}

# Use the service account in your GKE cluster module
module "gke_cluster" {
  source               = "./modules/gke-cluster"
  node_service_account = module.gke_node_service_account.email
}
```

---

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | The Google Cloud project ID. | `string` | - | Yes |
| `project_number` | The Google Cloud project number. | `string` | - | Yes |
| `service_account_name` | The ID for the service account (name before @). | `string` | `"gke-nodes"` | No |
| `service_account_display_name` | Display name for the service account. | `string` | `"GKE Node Service Account"` | No |
| `service_account_description` | Description for the service account. | `string` | `"Dedicated service account for GKE node pools with least-privilege permissions"` | No |
| `enable_secret_manager` | Set to `true` to grant Secret Manager accessor roles. | `bool` | `true` | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `email` | The email address of the created service account. |
| `name` | The full resource name of the service account. |
| `id` | The unique ID of the service account. |

---

## IAM Roles Granted

The module grants the following roles to the service account to ensure least-privilege access:

- `roles/container.nodeServiceAccount`: Provides core permissions for GKE node operations.
- `roles/artifactregistry.reader`: Allows the node to pull container images from Artifact Registry.
- `roles/logging.logWriter`: Enables nodes to write logs to Cloud Logging.
- `roles/monitoring.metricWriter`: Enables nodes to write metrics to Cloud Monitoring.
- `roles/storage.objectViewer`: Allows nodes to download models or configurations from GCS.
- `roles/secretmanager.secretAccessor`: (Optional) Grants access to secrets via the Secret Manager CSI driver.

---

## Security Benefits

By using a dedicated service account, you achieve:
1.  **Least Privilege:** You only grant the specific permissions required for GKE nodes.
2.  **Auditability:** You can clearly attribute infrastructure actions to your GKE nodes.
3.  **Isolation:** You isolate your node pool's identity from other workloads that might use the default service account.

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
