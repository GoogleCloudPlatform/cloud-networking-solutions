# Semantic Cache Module

This module creates the infrastructure for semantic caching using Vertex AI Vector Search and Apigee API Management. It enables intelligent caching of LLM responses based on the semantic similarity of prompts.

## Overview

The Semantic Cache module provisions:

- **Vertex AI Vector Search:** An index and endpoint for semantic similarity search.
- **Apigee Organization:** API management components including environments and instances.
- **Private Service Connect (PSC):** A dedicated PSC subnet and endpoints for private connectivity.
- **Service Accounts:** Dedicated accounts for the Apigee proxy runtime and API Management operator.
- **DNS Zones:** Private DNS zones for Apigee DNS peering.
- **Internal Load Balancer:** An optional internal HTTPS load balancer for private Apigee access.

---

## Architecture

1.  **Vertex AI Vector Search:** Host the semantic cache index with 768 dimensions and DOT_PRODUCT distance measure.
2.  **Apigee Organization:** Manage your API environments and runtime instances.
3.  **Private Service Connect:** Ensure all traffic between your VPC and Google services stays private.
4.  **GCS Index Storage:** Store your vector index data in a versioned bucket.
5.  **Internal Load Balancer:** Optionally provide an internal HTTPS endpoint for the Apigee runtime.

---

## Usage Guide

### Basic Configuration

```hcl
module "semantic_cache" {
  source = "./modules/semantic-cache"

  project_id = "YOUR_PROJECT_ID"
  region     = "YOUR_REGION"

  # Apigee Configuration (object-based)
  apigee = {
    organization = {
      billing_type        = "PAYG"
      disable_vpc_peering = true  # Use Non-VPC Peering mode (recommended)
    }

    envgroups = {
      prod = ["api.gateway.example.com"]
    }

    environments = {
      apis-prod = {
        display_name = "APIs Production"
        envgroups    = ["prod"]
        type         = "INTERMEDIATE"
      }
    }

    instances = {
      us-east4 = {
        environments = ["apis-prod"]
      }
    }
  }

  # Vertex AI Configuration (object-based)
  vertex_ai = {
    index = {
      dimensions            = 768
      distance_measure_type = "DOT_PRODUCT_DISTANCE"
    }
    deployed_index = {
      min_replica_count = 1
      max_replica_count = 3
    }
  }
}
```

---

## Variables

### Required Variables
| Name | Description | Type |
|------|-------------|------|
| `project_id` | The Google Cloud project ID. | `string` |
| `region` | The GCP region for resources. | `string` |

### Optional Variables
| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vpc_id` | VPC network ID (only used when Apigee VPC peering is enabled). | `string` | `null` |
| `labels` | Labels to apply to all resources. | `map(string)` | `{}` |

### Apigee Configuration
| Name | Description | Type | Default |
|------|-------------|------|---------|
| `apigee` | Apigee configuration object (see below). | `object` | `{}` |

The `apigee` object supports the following nested attributes:

- **`organization`**: Apigee organization settings (`billing_type`, `disable_vpc_peering`, `runtime_type`, etc.)
- **`envgroups`**: Map of environment group names to hostnames
- **`environments`**: Map of environment configurations (`display_name`, `envgroups`, `type`, `properties`)
- **`instances`**: Map of instance configurations by region (`environments`, `runtime_ip_cidr_range`, `consumer_accept_list`)
- **`endpoint_attachments`**: Map of PSC endpoint attachments (`region`, `service_attachment`)
- **`dns_zones`**: Map of DNS peering zones (`domain`, `description`, `target_project_id`, `target_network_id`)

### Vertex AI Configuration
| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vertex_ai` | Vertex AI vector search configuration object (see below). | `object` | `{}` |

The `vertex_ai` object supports the following nested attributes:

- **`bucket_name`**: Custom GCS bucket name (auto-generated if null)
- **`bucket_force_destroy`**: Allow bucket destruction with contents (default: `false`)
- **`index`**: Index configuration including `dimensions` (default: `768`), `distance_measure_type` (default: `DOT_PRODUCT_DISTANCE`), `approximate_neighbors_count`, `feature_norm_type`, `shard_size`, `update_method`
- **`endpoint`**: Endpoint display name
- **`deployed_index`**: Deployed index configuration including `min_replica_count` (default: `1`), `max_replica_count` (default: `3`), `enable_access_logging`

### Service Account Configuration
| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_service_accounts` | Create service accounts for Apigee and semantic cache operations. | `bool` | `true` |
| `create_apim_operator_iam` | Create IAM bindings for Apigee APIM Operator. | `bool` | `true` |
| `enable_apim_workload_identity` | Enable the Workload Identity IAM binding for the APIM Operator. | `bool` | `true` |
| `apim_operator_namespace` | Kubernetes namespace for APIM Operator service account. | `string` | `"apim"` |
| `apim_operator_ksa` | Kubernetes service account name for APIM Operator. | `string` | `"apim-ksa"` |

### PSC Subnet Requirements

When using Non-VPC Peering mode (the default), Apigee connects to your backend services via Private Service Connect (PSC). The PSC subnet is configured through the `apigee.instances` settings. Key considerations:

- PSC subnets must not overlap with other subnets in your VPC.
- In Non-VPC Peering mode, `runtime_ip_cidr_range` and `troubleshooting_ip_cidr_range` are not required in instance configuration.
- Use `apigee.endpoint_attachments` to connect Apigee to service attachments in your VPC.
- DNS peering zones (via `apigee.dns_zones`) allow Apigee proxies to resolve private DNS names.

---

## Outputs

### Vertex AI Outputs
| Name | Description |
|------|-------------|
| `vertex_ai_index_id` | The ID of the Vertex AI semantic cache index. |
| `vertex_ai_public_endpoint_network_config` | The public endpoint domain name for vector search. |
| `semantic_cache_bucket_name` | The GCS bucket name for index data. |

### Apigee Outputs
| Name | Description |
|------|-------------|
| `apigee_organization_id` | The Apigee organization ID. |
| `apigee_endpoint` | The Apigee runtime endpoint URL. |

---

## Service Accounts

| Service Account | Purpose |
|-----------------|---------|
| `apigee-proxy-runtime` | Used for deploying Apigee proxies and accessing Vertex AI for semantic caching. |
| `apigee-apim-gsa` | Used by the API Management operator with Workload Identity. |

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
