# Foundation Module (`modules/foundation`)

This module provisions the foundational Google Cloud resource hierarchy for the network lab environment.

It creates the 3-level folder hierarchy and core networking projects for the `on-prem`, `production`, and `development` environments, enables required Google Cloud APIs, and configures Shared VPC host projects. Application service projects are created and attached in the subsequent `networking` stage ([`modules/networking`](../networking)).

## Overview

By default, this module provisions **~55 resources**:
*   **7 Resource Manager Folders**: A 3-level folder hierarchy (`fldr-[prefix]-network-lab` at Level 1, 3 environment folders at Level 2, and 4 shared-infra/application folders at Level 3).
*   **5 Core Projects**: `prj-[prefix]-p-net-host`, `prj-[prefix]-p-net-transit`, `prj-[prefix]-d-net-host`, `prj-[prefix]-d-net-transit`, and `prj-[prefix]-on-prem` (each with a 4-character random hex suffix).
*   **2 Shared VPC Host Attachments**: Enables `prj-[prefix]-p-net-host` and `prj-[prefix]-d-net-host` as Shared VPC host projects.
*   **25 API Activations**: Enables Compute, Network Security, Cloud DNS, Network Connectivity, and Cloud Resource Manager APIs across all 5 core projects.

### Folders (`folders.tf`)

This module creates a 3-level folder structure within the Google Cloud Organization:

*   **Level 1 Folder**:
    *   **Name**: `fldr-[prefix]-network-lab`
    *   **Parent**: Organization (`var.organization_id`)

*   **Level 2 Folders**:
    *   **Parent**: `fldr-[prefix]-network-lab`
    *   **Names**:
        *   `fldr-[prefix]-on-prem`
        *   `fldr-[prefix]-production`
        *   `fldr-[prefix]-development`

*   **Level 3 Production Folders**:
    *   **Parent**: `fldr-[prefix]-production`
    *   **Names**:
        *   `fldr-[prefix]-p-application`
        *   `fldr-[prefix]-p-shared-infra`

*   **Level 3 Development Folders**:
    *   **Parent**: `fldr-[prefix]-development`
    *   **Names**:
        *   `fldr-[prefix]-d-application`
        *   `fldr-[prefix]-d-shared-infra`

### Projects (`projects.tf`)

This module provisions 5 core Google Cloud projects via `local.core_projects` and `module "projects"` with `random_project_id = true` (which appends a 4-character random hex suffix to each project ID) and common labels `purpose = "network-lab"` and `created = "terraform"`. Each project is also tagged with a specific `labels.environment` value, which Stage 2 (`modules/networking`) uses via `google_projects` data sources to dynamically discover project IDs without requiring `terraform_remote_state`:

*   **Production Host Project**:
    *   **Name**: `prj-[prefix]-p-net-host`
    *   **Folder**: `fldr-[prefix]-p-shared-infra`
    *   **Label (`environment`)**: `prod-host`
    *   **Shared VPC**: Enabled as a Shared VPC host project.

*   **Production Transit Project**:
    *   **Name**: `prj-[prefix]-p-net-transit`
    *   **Folder**: `fldr-[prefix]-p-shared-infra`
    *   **Label (`environment`)**: `prod-transit`

*   **Development Host Project**:
    *   **Name**: `prj-[prefix]-d-net-host`
    *   **Folder**: `fldr-[prefix]-d-shared-infra`
    *   **Label (`environment`)**: `dev-host`
    *   **Shared VPC**: Enabled as a Shared VPC host project.

*   **Development Transit Project**:
    *   **Name**: `prj-[prefix]-d-net-transit`
    *   **Folder**: `fldr-[prefix]-d-shared-infra`
    *   **Label (`environment`)**: `dev-transit`

*   **On-Prem Project**:
    *   **Name**: `prj-[prefix]-on-prem`
    *   **Folder**: `fldr-[prefix]-on-prem`
    *   **Label (`environment`)**: `on-prem`

### Activated APIs (`locals.tf`)

The following APIs are automatically enabled on all 5 core projects:
*   `compute.googleapis.com`
*   `networksecurity.googleapis.com`
*   `dns.googleapis.com`
*   `networkconnectivity.googleapis.com`
*   `cloudresourcemanager.googleapis.com`

### Organization Policy Reset (`folders.tf` & `outputs.tf`)

To allow HA VPN tunnels with simulated peer IPs in the lab folder without requiring Service Account impersonation for the Org Policy API during `terraform apply`, this module outputs a ready-to-run `gcloud` command (`org_policy_reset_command`) that resets `compute.restrictVpnPeerIPs` on `fldr-[prefix]-network-lab`:

```bash
$(terraform output -raw org_policy_reset_command)
```

## Usage

```hcl
module "foundation" {
  source = "../../../modules/foundation"

  organization_id     = var.organization_id
  billing_account_id  = var.billing_account_id
  prefix              = var.prefix
  deletion_protection = false
}
```

For a complete end-to-end deployment template (which is copied into `examples/<lab_name>` and configured with your remote GCS backend and `terraform.tfvars`), see **[examples/ncc/01-foundation](../../examples/ncc/01-foundation)**, **[examples/vpc-peering/01-foundation](../../examples/vpc-peering/01-foundation)**, and **[examples/ncc/README.md](../../examples/ncc/README.md)**.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| google | >= 6.0, < 9.0 |
| google-beta | >= 6.0, < 9.0 |

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| billing\_account\_id | The ID of the billing account to associate projects with. | `string` | n/a | yes |
| deletion\_protection | Whether to enable deletion protection on folders and projects. | `bool` | `false` | no |
| organization\_id | The organization ID. | `string` | n/a | yes |
| prefix | Prefix for folders and projects. | `string` | `"lab"` | no |

## Outputs

| Name | Description |
|------|-------------|
| base\_folder\_id | The ID of the base folder. |
| dev\_level3\_folder\_ids | A map of development level 3 folder names to their IDs. |
| dev\_project\_ids | Map of development project roles and names to their project IDs. |
| level2\_folder\_ids | A map of level 2 folder names to their IDs. |
| on\_prem\_project\_id | The project ID of the on-prem project. |
| org\_policy\_reset\_command | Run this gcloud command to reset compute.restrictVpnPeerIPs on the base folder when deploying with user credentials. |
| prod\_level3\_folder\_ids | A map of production level 3 folder names to their IDs. |
| prod\_project\_ids | Map of production project roles and names to their project IDs. |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
