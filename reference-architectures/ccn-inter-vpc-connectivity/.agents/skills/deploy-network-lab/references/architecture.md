# Network Lab Architecture & Resource Reference

Load this reference when the user asks to **describe the code**, **explain the network lab architecture**, or review the **resource inventory and IAM requirements** in detail. Combine this summary with the authoritative tables in the root `README.md`, `modules/foundation/README.md`, and `modules/networking/README.md`.

## 1. Two-Stage Architecture Overview

- **`01-foundation`**: Provisions the 3-level Landing Zone folder hierarchy (`fldr-{prefix}-network-lab` at L1, 3 L2 environment folders, and 4 L3 folders), creates the 5 foundational projects (`on-prem`, `prod-host`, `prod-transit`, `dev-host`, `dev-transit` — each suffixed with a random 4-hex ID), links Cloud Billing, activates required Google Cloud APIs, and enables Shared VPC host mode on `prod-host` and `dev-host`.
- **`02-networking`**: Dynamically discovers `01-foundation` folders and projects via `data` sources (matching `fldr-${var.prefix}-*`) and deploys the multi-region (`us-east4` and `us-west1`) production and simulated on-premises network topology:
  - **2 Production Service Projects** (`prj-{prefix}-p-svc-app-01`, `prj-{prefix}-p-svc-app-02`) attached to the Prod Shared VPC Host project.
  - **6 VPC Networks** (`vpc-on-prem`, `vpc-p-transit`, `vpc-p-services`, `vpc-p-svpc-app-01`, `vpc-p-svpc-app-02`, `vpc-p-svpc-app-03`) configured with `BEFORE_CLASSIC_FIREWALL` policy enforcement order.
  - **52 Subnets** across `us-east4` and `us-west1` (28 base, `REGIONAL_MANAGED_PROXY`, and `PRIVATE_SERVICE_CONNECT` subnets + 24 optional CGN `100.64.x.x/24` and PUPI `1.2.x.x/24` subnets enabled by default; Private Google Access enabled on all 46 standard VM subnets).
  - **Hybrid Connectivity**: 8 HA VPN Gateways, 16 HA VPN Tunnels, and 6 dedicated BGP Cloud Routers (`ASN 65001` On-Prem ↔ `ASN 65002` Transit ↔ `ASN 65003` Services).
  - **Outbound Egress**: 12 regional Cloud NAT Gateways on 12 dedicated NAT Cloud Routers (`ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging).
  - **Mutually Exclusive Inter-VPC Connectivity**:
    - **Option A — NCC Hub & Spokes (`examples/ncc`, `enable_ncc = true`)**: 1 NCC Hub (`ncc-hub-prod`) in `MESH` preset topology (`export_psc = true`, auto-accepting `prod-host` and `prod-transit` spokes) with **8 Spokes** (4 Hybrid VPN spokes with `site_to_site_data_transfer = true` + 4 VPC spokes: `transit`, `app1`, `app2`, `app3`).
    - **Option B — Hub-and-Spoke VPC Network Peering (`examples/vpc-peering`, `enable_vpc_peering = true`)**: **6 VPC Network Peerings** (`vpc-p-transit` ↔ `app1`, `app2`, `app3`) with `export_custom_routes = true` and `import_custom_routes = true`.
  - **Layered Firewall Policies & Secure Tags**:
    - **2 Organization-Scoped `GCE_FIREWALL` Tag Keys** (`{prefix}-quarantine`, `{prefix}-workload`, `purpose_data = { organization = "auto" }`) and **9 Tag Values** (`quarantine`, `on-prem-webserver`, `on-prem-client`, `app1-webserver`, `app1-client`, `app2-webserver`, `app2-client`, `app3-webserver`, `app3-client`).
    - **1 Hierarchical Firewall Policy** (`hfwp-{prefix}-network-lab`) attached to `fldr-{prefix}-network-lab` (**9 rules**: quarantine ingress/egress `500`/`501`, Google LB/NLB proxy & health check ingress `1000`/`2000`, IAP SSH/RDP `3000`, and Geo/Threat-Intel ingress/egress blocks `3100`–`3400`).
    - **6 Global Network Firewall Policies** (`gfwp-<vpc_name>`, one per VPC, **13 rules total**: 1 in `on_prem`, 3 in `prod_transit`, 0 in `prod_services`, 2 in `prod_app1`, 3 in `prod_app2`, and 4 in `prod_app3` isolating `app3` inside the mesh).

## 2. Resource Counts by Stage & Topology

| Stage / Example | Approximate Resource Count | Key Outputs |
| :--- | :--- | :--- |
| **`01-foundation`** | **~55 resources** | `base_folder_id`, `level2_folder_ids`, `prod_level3_folder_ids`, `dev_level3_folder_ids`, `on_prem_project_id`, `prod_project_ids`, `dev_project_ids`, `org_policy_reset_command` |
| **`02-networking` (`examples/ncc`)** | **~224 resources** | `project_ids`, `prod_service_project_ids`, `vpc_self_links`, `subnets`, `ncc_hub_id`, `hierarchical_firewall_policy_id`, `network_firewall_policies`, `firewall_secure_tags` |
| **`02-networking` (`examples/vpc-peering`)** | **~220 resources** | Same as above, with `vpc_peerings` populated and `ncc_hub_id = null` |

## 3. Required Organization & Billing IAM Roles

| Scope | Role | Required For |
| :--- | :--- | :--- |
| Organization | `roles/resourcemanager.folderAdmin` | Creating L1–L3 folders |
| Organization | `roles/resourcemanager.projectCreator` | Provisioning foundational and service projects |
| Organization | `roles/resourcemanager.projectDeleter` | Destroying lab projects during teardown |
| Organization | `roles/compute.xpnAdmin` | Enabling Shared VPC host projects & attaching service projects |
| Organization | `roles/compute.networkAdmin` | Managing VPCs, subnets, HA VPNs, Cloud Routers/NATs, peerings, and Global Network Firewall Policies |
| Organization | `roles/compute.orgSecurityPolicyAdmin` | Creating Hierarchical Firewall Policy and rules |
| Organization | `roles/compute.orgSecurityResourceAdmin` | Associating Hierarchical Firewall Policy with L1 folder |
| Organization | `roles/resourcemanager.tagAdmin` | Creating org-scoped `GCE_FIREWALL` TagKeys and TagValues |
| Organization | `roles/resourcemanager.tagUser` | Binding/referencing `GCE_FIREWALL` Secure Tags across policies and workloads |
| Organization | `roles/networkconnectivity.admin` | Creating NCC Hub, Groups, and Spokes *(required only when `enable_ncc = true`)* |
| Organization | `roles/orgpolicy.policyAdmin` | Resetting `compute.restrictVpnPeerIPs` on the L1 lab folder *(when enforced by org)* |
| Billing Account | `roles/billing.user` | Linking newly created lab projects to Cloud Billing |
| GCS State Bucket | `roles/storage.objectAdmin` (+ `legacyBucketReader` when scoped to bucket) | Reading/writing Terraform remote state files |

## 4. End-to-End Lifecycle Summary (For User Explanations)

1. **Discover & Validate Prerequisites**: Auto-discover active GCP project, org, and billing IDs; run `check_prereqs.py` to verify Terraform `>= 1.5`, `gcloud`, ADC, optional SA impersonation (CLI + ADC), org/billing/bucket IAM, and `prefix` uniqueness (`^[a-z0-9]{1,7}$`).
2. **Initialize Lab Workspace & Remote State**: Copy `examples/ncc` or `examples/vpc-peering` to `examples/{lab_name}`, create/verify the GCS bucket (`--location=us-east4 --uniform-bucket-level-access --public-access-prevention`), and configure `backend.tf` (`{lab_name}/foundation` and `{lab_name}/networking`) and matching `terraform.tfvars`.
3. **Apply `01-foundation`**: Plan, summarize with `summarize_plan.py`, and apply Stage 1.
4. **Reset Org Policy (If Enforced)**: Check effective `compute.restrictVpnPeerIPs` on the L1 folder; if restricted, reset it and wait 45 seconds for regional Compute Engine policy cache propagation.
5. **Apply `02-networking`**: Plan, summarize with `summarize_plan.py`, and apply Stage 2.
6. **Verify Connectivity & Security**: Run `verify_deployment.py` to confirm all 16 VPN tunnels are `ESTABLISHED`, all 6 BGP routers have `Established` peers with `learned routes > 0`, all 8 NCC spokes (or 6 VPC peerings) are `ACTIVE`, and Hierarchical + 6 Global Network Firewall Policies are associated.
7. **Teardown**: Run `check_teardown.py` (using `--clean` if confirmed) to clear unmanaged VMs, classic firewall rules, forwarding rules, Secure Tag bindings, and project liens; destroy `02-networking` then `01-foundation`; optionally delete remote state and `examples/{lab_name}`.
