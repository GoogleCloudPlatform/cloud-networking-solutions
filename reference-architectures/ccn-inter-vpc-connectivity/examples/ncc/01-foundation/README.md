# Stage 1: Foundation Terraform Configuration (`01-foundation`)

This directory contains the Stage 1 Terraform configuration for setting up the foundational Google Cloud environment using [`modules/foundation`](../../../modules/foundation).

It creates the 3-level folder hierarchy and core networking projects for the `on-prem`, `production`, and `development` environments, enables required Google Cloud APIs, and configures Shared VPC host projects. Application service projects are created and attached in Stage 2 ([`02-networking`](../02-networking)).

For a detailed breakdown of the provisioned folders, projects, and APIs, see the **[Foundation Module Documentation (`modules/foundation`)](../../../modules/foundation/README.md)**.

## Usage

To deploy this stage as part of a lab environment, copy the `examples/ncc` template into a dedicated lab directory, configure `backend.tf`, and create a `terraform.tfvars` file:

```hcl
organization_id    = "YOUR_ORGANIZATION_ID"
billing_account_id = "YOUR_BILLING_ACCOUNT_ID"
prefix             = "ncc" # Optional naming prefix (defaults to "ncc")
```

For complete step-by-step deployment instructions (including template initialization, GCS backend setup, and organization policy resets), see the **[NCC Lab Example Deployment Guide (`examples/ncc/README.md`)](../README.md#stage-1-core-foundation-01-foundation)**.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| billing\_account\_id | The ID of the billing account to associate projects with. | `string` | n/a | yes |
| organization\_id | The organization ID. | `string` | n/a | yes |
| prefix | Prefix for folders and projects. | `string` | `"ncc"` | no |

## Outputs

| Name | Description |
|------|-------------|
| base\_folder\_id | The ID of the base folder. |
| dev\_level3\_folder\_ids | A map of development level 3 folder names to their IDs. |
| dev\_project\_ids | A map of development project names to their IDs. |
| level2\_folder\_ids | A map of level 2 folder names to their IDs. |
| on\_prem\_project\_id | The project ID of the on-prem project. |
| org\_policy\_reset\_command | Run this gcloud command to reset compute.restrictVpnPeerIPs on the base folder when deploying with user credentials. |
| prod\_level3\_folder\_ids | A map of production level 3 folder names to their IDs. |
| prod\_project\_ids | A map of production project names to their IDs. |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
