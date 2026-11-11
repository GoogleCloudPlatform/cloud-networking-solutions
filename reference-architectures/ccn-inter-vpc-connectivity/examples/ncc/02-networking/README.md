# Stage 2: Networking Configuration (`02-networking`)

This directory contains the Stage 2 Terraform configuration for the `production` and simulated `on-prem` environments using [`modules/networking`](../../../modules/networking) with **`enable_ncc = true`**.

This stage must be applied *after* Stage 1 ([`01-foundation`](../01-foundation)) has been successfully applied, as it dynamically discovers the folders and projects created by `01-foundation`.

For a detailed breakdown of the provisioned VPCs, subnet IP ranges, Cloud NAT gateways, HA VPN tunnels, BGP sessions, Hierarchical and Global Network Firewall Policies, Secure Tags, and Network Connectivity Center (NCC) Hub and Spokes, see the **[Networking Module Documentation (`modules/networking`)](../../../modules/networking/README.md)**.

## Usage

To deploy this stage as part of a lab environment, configure `backend.tf` and create a `terraform.tfvars` file (matching the `prefix` used in `01-foundation`):

```hcl
organization_id    = "YOUR_ORGANIZATION_ID"
billing_account_id = "YOUR_BILLING_ACCOUNT_ID"
prefix             = "ncc" # Must match the prefix used in 01-foundation (defaults to "ncc")
```

For complete step-by-step deployment and verification instructions, see the **[NCC Lab Example Deployment Guide (`examples/ncc/README.md`)](../README.md#stage-2-networking-02-networking)**.

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
| firewall\_secure\_tags | Map of Firewall Secure Tag value IDs (tagValues/<id>) for quarantine and workloads. |
| hierarchical\_firewall\_policy\_id | The ID of the L1 base folder Hierarchical Firewall Policy. |
| ncc\_hub\_id | The ID of the Production NCC Hub (null if enable\_ncc is false). |
| network\_firewall\_policies | Map of Global Network Firewall Policy names keyed by VPC. |
| on\_prem\_vpc\_network\_name | The name of the on-prem VPC network. |
| prod\_service\_project\_ids | The IDs of the Production service projects. |
| prod\_vpc\_names | The names of the Production VPCs. |
| project\_ids | Discovered and created project IDs across environments. |
| subnets | Map of subnet self-links keyed by '<region>/<subnet\_name>' per VPC. |
| vpc\_peerings | Map of VPC Network Peering names between prod\_transit and application VPCs (empty if enable\_vpc\_peering is false). |
| vpc\_self\_links | Self-links of all provisioned VPC networks. |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
