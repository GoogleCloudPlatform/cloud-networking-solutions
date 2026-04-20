# Service Extension Module

This module provides a flexible way to deploy external processing (ext_proc) services on Cloud Run with integration for load balancers and traffic extensions. Use this module to support advanced service routing, transformation, and validation scenarios.

## Features

- **Cloud Run Deployment:** Deploy gRPC services on Cloud Run.
- **Automated IAM:** Automatically create service accounts with necessary logging and monitoring permissions.
- **Autoscaling:** Configure resource limits and autoscaling to meet demand.
- **LB Integration:** Create regional backend services and Serverless Network Endpoint Groups (NEGs) for load balancer integration.
- **Flexible Extensions:** Support advanced routing and traffic extension scenarios via ext-proc.

## Use Cases

- Body-Based Routing (BBR) for extracting model names from request payloads.
- Custom request and response transformations.
- Header injection for intelligent routing decisions.
- Content filtering and validation.

---

## Prerequisites

Before you use this module, ensure you have:
- Terraform (>= 1.0)
- Google Cloud Provider (>= 4.0)
- A Google Cloud project with the Cloud Run API enabled.

---

## Variables

| Name | Type | Description | Default | Required |
|------|------|-------------|---------|----------|
| `project_id` | `string` | The Google Cloud project ID. | - | Yes |
| `region` | `string` | The region for resource deployment. | - | Yes |
| `service_name` | `string` | The name identifier for the service extension (e.g., `bbr`). | - | Yes |
| `name_prefix` | `string` | Prefix for resource naming. | `"ext"` | No |
| `labels` | `map(string)` | Labels to apply to all resources. | `{}` | No |
| `create_service_account` | `bool` | Create a new service account for the ext_proc service. | `true` | No |
| `service_account_email` | `string` | Existing service account email (required if `create_service_account = false`). | `null` | No |
| `cloud_run` | `object` | Cloud Run service configuration (see below). | - | Yes |
| `grant_iap_invoker` | `bool` | Grant Cloud Run invoker role to IAP service agent. | `true` | No |
| `grant_compute_invoker` | `bool` | Grant Cloud Run invoker role to Compute Engine default service account. | `true` | No |
| `create_backend_service` | `bool` | Create a regional backend service and serverless NEG. | `true` | No |
| `backend_service` | `object` | Backend service configuration for LB ext_proc callouts (see below). | `{}` | No |

### `cloud_run` Object Structure

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `image` | `string` | Container image for the ext_proc service. | - (required) |
| `command` | `list(string)` | Optional command to override container entrypoint. | `null` |
| `port` | `number` | Container port for gRPC. | `8080` |
| `cpu_limit` | `string` | CPU limit. | `"1000m"` |
| `memory_limit` | `string` | Memory limit. | `"512Mi"` |
| `min_instances` | `number` | Minimum instances for autoscaling. | `1` |
| `max_instances` | `number` | Maximum instances for autoscaling. | `10` |
| `concurrency` | `number` | Container concurrency. | `100` |
| `timeout_seconds` | `number` | Request timeout in seconds. | `30` |
| `log_level` | `string` | Log level (`DEBUG`, `INFO`, `WARNING`, `ERROR`). | `"INFO"` |
| `environment_variables` | `map(string)` | Additional environment variables. | `{}` |

### `backend_service` Object Structure

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `load_balancing_scheme` | `string` | LB scheme (`EXTERNAL_MANAGED`, `INTERNAL_MANAGED`, `INTERNAL_SELF_MANAGED`). | `"EXTERNAL_MANAGED"` |
| `timeout_sec` | `number` | Backend timeout in seconds. | `30` |
| `enable_logging` | `bool` | Enable backend logging. | `true` |
| `log_sample_rate` | `number` | Log sampling rate 0.0-1.0. | `1.0` |

### NEG and Load Balancer Integration

When `create_backend_service = true`, the module creates:

1. A **Serverless Network Endpoint Group (NEG)** pointing to the Cloud Run service.
2. A **regional backend service** that uses the NEG as its backend.

The backend service can then be referenced by a load balancer's route extension (e.g., `LbRouteExtension`) to intercept and process traffic via the ext_proc protocol. The `load_balancing_scheme` must match the scheme of the parent load balancer.

---

## Outputs

| Name | Description |
|------|-------------|
| `service_account_email` | The email of the created ext_proc service account. |
| `cloud_run_service_url` | The URL of the deployed Cloud Run service. |
| `backend_service_id` | The ID of the regional backend service. |
| `neg_id` | The ID of the serverless Network Endpoint Group (NEG). |

---

## Usage Example

```hcl
module "body_based_routing" {
  source = "./modules/service-extension"

  project_id    = "YOUR_PROJECT_ID"
  region        = "YOUR_REGION"
  service_name  = "bbr"

  cloud_run = {
    image             = "YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/images/bbr:latest"
    cpu_limit         = "1000m"
    memory_limit      = "512Mi"
    min_instances     = 1
    max_instances     = 10
    log_level         = "INFO"
  }

  backend_service = {
    load_balancing_scheme = "EXTERNAL_MANAGED"
    timeout_sec           = 30
    enable_logging        = true
  }
}
```

---

## Troubleshooting

- **API Enablement:** Verify that the Cloud Run API is enabled in your project.
- **IAM Permissions:** Check that your service account has the necessary permissions to invoke Cloud Run.
- **gRPC Compatibility:** Ensure your service is compatible with gRPC and HTTP/2.

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
