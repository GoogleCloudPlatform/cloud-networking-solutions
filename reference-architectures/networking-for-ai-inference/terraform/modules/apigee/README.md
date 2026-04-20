# Apigee Module: API Management and Governance

This Terraform module provides a comprehensive solution for managing Apigee organizations, environments, environment groups, instances, and service accounts. It supports both traditional VPC peering and Non-VPC Peering (Private Service Connect) modes.

## Features

- **Multi-Mode Support:** Switch between VPC Peering and Non-VPC Peering (PSC) modes.
- **Automated Service Accounts:** Create and configure Google Service Accounts (GSAs) for proxy runtime and API Management operators.
- **Workload Identity:** Use native support for GKE-based service account bindings.
- **Dynamic Networking:** Manage DNS peering zones and PSC endpoint attachments automatically.
- **Granular Control:** Configure environments and runtime instances with fine-tuned settings.

---

## Quick Start

### Basic Usage Example
```hcl
module "apigee" {
  source = "./modules/apigee"

  project_id        = "YOUR_PROJECT_ID"
  project_number    = "YOUR_PROJECT_NUMBER"
  region            = "YOUR_REGION"

  organization = {
    display_name         = "My Apigee Org"
    billing_type        = "PAYG"
    disable_vpc_peering = true
  }

  envgroups = {
    prod = ["api.example.com"]
  }

  environments = {
    apis-prod = {
      display_name = "APIs Production"
      envgroups    = ["prod"]
    }
  }
}
```

---

## Variables

### Core Configuration
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `project_id` | `string` | The Google Cloud project ID. | - | Yes |
| `project_number` | `string` | The project number for service agent IAM bindings. | - | Yes |
| `region` | `string` | The region for Apigee resources. | - | Yes |

### Organization Settings
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `organization` | `object` | Apigee organization configuration (see below). | `{}` | No |
| `vpc_id` | `string` | VPC network ID (only used when `disable_vpc_peering` is false). | `null` | No |

The `organization` object supports:
| Attribute | Type | Description | Default |
|:--- | :--- | :--- | :--- |
| `display_name` | `string` | Display name for the organization. | `"Apigee Organization"` |
| `description` | `string` | Description for the organization. | `"Apigee Organization for API Management"` |
| `billing_type` | `string` | `PAYG` or `SUBSCRIPTION`. | `"PAYG"` |
| `analytics_region` | `string` | Analytics region (defaults to `var.region`). | `null` |
| `runtime_type` | `string` | `CLOUD` or `HYBRID`. | `"CLOUD"` |
| `disable_vpc_peering` | `bool` | Set to `true` for Non-VPC Peering/PSC mode (recommended). | `true` |
| `database_encryption_key` | `string` | Optional KMS key for database encryption. | `null` |

### Environment Groups
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `envgroups` | `map(list(string))` | Map of environment group names to hostnames. | `{}` | No |

### Environments
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `environments` | `map(object)` | Map of Apigee environments (see below). | `{}` | No |

Each environment object supports: `display_name` (required), `description`, `envgroups` (required, list of group names), `type` (`INTERMEDIATE` or `COMPREHENSIVE`, default `INTERMEDIATE`), `node_config`, `properties`.

### Instances
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `instances` | `map(object)` | Map of Apigee instances by region. | `{}` | No |

Each instance object supports: `environments` (required), `runtime_ip_cidr_range`, `troubleshooting_ip_cidr_range`, `consumer_accept_list`, `disk_encryption_key`.

### Endpoint Attachments
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `endpoint_attachments` | `map(object)` | PSC endpoint attachments for backend services. | `{}` | No |

Each attachment requires: `region` and `service_attachment`.

### DNS Zones
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `dns_zones` | `map(object)` | DNS zones for Apigee DNS peering. | `{}` | No |

Each zone requires: `domain`, `description`, `target_project_id`, `target_network_id`.

### Service Accounts and APIM
| Name | Type | Description | Default | Required |
|:--- | :--- | :--- | :--- | :--- |
| `create_service_accounts` | `bool` | Create service accounts for Apigee proxy runtime. | `true` | No |
| `service_account_prefix` | `string` | Prefix for service account names. | `"apigee"` | No |
| `create_apim_operator_iam` | `bool` | Create IAM bindings for Apigee APIM Operator. | `true` | No |
| `enable_apim_workload_identity` | `bool` | Enable the Workload Identity IAM binding for the APIM Operator. | `true` | No |
| `apim_operator_namespace` | `string` | Kubernetes namespace for APIM Operator service account. | `"apim"` | No |
| `apim_operator_ksa` | `string` | Kubernetes service account name for APIM Operator. | `"apim-ksa"` | No |

---

## Outputs

| Name | Description |
|:--- | :--- |
| `org_id` | The Apigee organization ID. |
| `org_name` | The Apigee organization name. |
| `organization_id` | The Apigee organization ID (full resource path). |
| `tenant_project_id` | The Apigee tenant project ID for PSC connections. |
| `service_agent_email` | The Apigee service agent email. |
| `envgroups` | Map of environment group names to their details. |
| `environments` | Map of Apigee environment names to their details. |
| `environment_ids` | Map of environment names to their IDs. |
| `instances` | Map of Apigee instance regions to their details. |
| `endpoint` | The Apigee runtime endpoint. |
| `endpoint_attachment_hosts` | Map of endpoint attachment names to their PSC endpoint hosts/IPs. |
| `proxy_runtime_sa_email` | The email of the Apigee proxy runtime service account. |
| `apim_operator_sa_email` | The email of the APIM Operator GSA. |
| `apim_operator_sa_name` | The full resource name of the APIM Operator GSA. |
| `dns_zones` | Map of DNS zone names to their details. |

---

## VPC Peering vs Non-VPC Peering Mode

This module supports two connectivity modes:

### Non-VPC Peering Mode (Recommended)

Set `organization.disable_vpc_peering = true` (the default). In this mode:

- Apigee connects to your backend services via **Private Service Connect (PSC)**.
- You do **not** need `runtime_ip_cidr_range` or `troubleshooting_ip_cidr_range` in instance configuration.
- Use `endpoint_attachments` to connect Apigee to service attachments in your VPC.
- Use `dns_zones` to allow Apigee proxies to resolve private DNS names in the target VPC.
- The Apigee service agent requires `roles/dns.peer` for DNS peering (configured automatically by this module).

### VPC Peering Mode

Set `organization.disable_vpc_peering = false`. In this mode:

- Apigee peers directly with your VPC network.
- You must provide `vpc_id` and configure `runtime_ip_cidr_range` in instance configuration.
- Direct network connectivity without PSC endpoint attachments.

---

## Security and Best Practices

- **Least Privilege:** All service accounts use minimal required IAM roles.
- **Encryption:** Supports database encryption via Customer Managed Encryption Keys (CMEK).
- **Private Access:** Default configurations use PSC to ensure API traffic stays within your private network.

---

**Version**: 1.1.0
