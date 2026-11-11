# Networking Module (`modules/networking`)

This module provisions the networking resources for the `production` and simulated `on-prem` environments.

It is intended to be applied *after* the [`modules/foundation`](../foundation) configuration has been applied, as it dynamically discovers the folders and projects created by `foundation` using `var.organization_id` and `var.prefix`.

## Overview

By default, this module provisions **~224 resources** across `us-east4` (primary) and `us-west1` (secondary):
*   **2 Service Projects**: `prj-[prefix]-p-svc-app-01` and `prj-[prefix]-p-svc-app-02` attached to the Production Shared VPC Host project (`prj-[prefix]-p-net-host`).
*   **6 VPC Networks & 52 Subnets**: `vpc-on-prem`, `vpc-p-transit`, `vpc-p-services`, `vpc-p-svpc-app-01`, `vpc-p-svpc-app-02`, and `vpc-p-svpc-app-03` (28 base/proxy/PSC subnets + 24 CGN and PUPI subnets enabled by default). All 6 VPCs use `GLOBAL` routing mode and `BEFORE_CLASSIC_FIREWALL` policy enforcement order, and all 46 standard VM subnets have **Private Google Access** enabled (`subnet_private_access = "true"`).
*   **8 HA VPN Gateways, 16 VPN Tunnels, & 6 BGP Cloud Routers**: Full-mesh regional HA VPN connectivity between `vpc-on-prem` ↔ `vpc-p-transit` and `vpc-p-services` ↔ `vpc-p-transit`.
*   **12 Cloud NAT Gateways & 12 NAT Cloud Routers**: Dedicated regional egress NAT in `us-east4` and `us-west1` for all 6 VPCs.
*   **Inter-VPC Connectivity (NCC or VPC Peering)**:
    *   **When `enable_ncc = true` (`examples/ncc`)**: Provisions **1 NCC Hub & 8 Spokes** (`ncc-hub-prod` in `MESH` topology with 4 VPC spokes and 4 Hybrid VPN spokes).
    *   **When `enable_vpc_peering = true` (`examples/vpc-peering`)**: Provisions **6 VPC Network Peerings** (3 bidirectional hub-and-spoke pairs connecting `vpc-p-transit` ↔ `vpc-p-svpc-app-01`, `vpc-p-svpc-app-02`, and `vpc-p-svpc-app-03` with custom route import/export enabled). *(Note: `enable_ncc` and `enable_vpc_peering` are mutually exclusive and cannot both be `true`.)*
*   **1 Hierarchical Firewall Policy & 6 Global Network Firewall Policies**: Folder-level Hierarchical Firewall Policy (`hfwp-[prefix]-network-lab`) on `fldr-[prefix]-network-lab` (9 rules) and 1 Global Network Firewall Policy (`gfwp-<vpc_name>`) associated with each of the 6 VPCs (12 rules total), backed by 2 `GCE_FIREWALL` Secure Tag keys (`[prefix]-quarantine` and `[prefix]-workload`) and 9 tag values.

*(Note: The `development` folders and projects created in `modules/foundation` are left empty by default as a sandbox for custom lab extensions.)*

### Folder & Project Discovery (`data.tf`)

Rather than relying on `terraform_remote_state`, this module dynamically discovers the foundational folders and projects created in Stage 1 (`modules/foundation`) using `var.organization_id` and `var.prefix`:

*   **Folders**: Looked up via `google_active_folder` data sources (`fldr-[prefix]-network-lab`, `fldr-[prefix]-production`, `fldr-[prefix]-on-prem`, `fldr-[prefix]-p-application`, and `fldr-[prefix]-p-shared-infra`).
*   **Projects**: Looked up via `google_projects` data sources filtered by parent folder ID, `labels.environment` (`prod-host`, `prod-transit`, `on-prem`), and `lifecycleState=ACTIVE`.

### IP Address Allocation & Subnet Naming Conventions (`vpcs.tf` & `variables.tf`)

#### 1. High-Level IP Address Plan (CIDR Ranges)

The lab segments IPv4 address space by function so that standard workloads, simulated on-premises networks, Envoy/PSC infrastructure ranges, CGNAT, and Privately Used Public IPs (PUPI) are immediately distinguishable in route tables, Firewall Insights, and packet captures:

| Address Block | Classification | Allocated CIDRs | Target VPCs | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **`10.0.0.0/8`** | RFC 1918 (Private) | • `10.10.0.0/16` (`vpc-p-transit`)<br>• `10.11.0.0/16` (`vpc-p-services`)<br>• `10.12.0.0/16` (`vpc-p-svpc-app-01`)<br>• `10.13.0.0/16` (`vpc-p-svpc-app-02`)<br>• `10.14.0.0/16` (`vpc-p-svpc-app-03`) | All Production VPCs | Primary `/24` subnets for standard production VM workloads (`client`, `web`, `std`) and Private Service Connect consumer endpoints (`psc-ep`). The second octet (`10`–`14`) uniquely identifies the Production VPC. |
| **`192.168.0.0/16`** | RFC 1918 (Private) | `192.168.0.0/24` – `192.168.3.0/24` | `vpc-on-prem` | Base `/24` subnets (`client` and `web`) for the simulated on-premises environment, kept distinct from `10.x.x.x` cloud ranges. |
| **`172.16.0.0/12`** | RFC 1918 (Private) | • `172.16.0.0/24` – `172.16.3.0/24` (`vpc-p-transit`)<br>• `172.17.0.0/24` – `172.17.1.0/24` (`vpc-p-svpc-app-02`) | `vpc-p-transit`, `vpc-p-svpc-app-02` | Dedicated to non-VM Google-managed infrastructure subnets: Regional Managed Proxy (`r-proxy`) and Private Service Connect Producer NAT (`psc-nat`). |
| **`100.64.0.0/10`** | RFC 6598 (Shared CGNAT Space) | • `100.64.0.0/24` – `100.64.3.0/24` (`vpc-on-prem`)<br>• `100.64.4.0/24` – `100.64.7.0/24` (`vpc-p-svpc-app-01`)<br>• `100.64.8.0/24` – `100.64.11.0/24` (`vpc-p-svpc-app-02`) | `vpc-on-prem`, `vpc-p-svpc-app-01`, `vpc-p-svpc-app-02` | Carrier-Grade NAT (`cgn`) subnets (controlled by `enable_*_cgn`) for testing private non-RFC 1918 traffic flows across VPCs and hybrid links. |
| **`1.2.0.0/16`** | Non-RFC 1918 (Simulated PUPI) | • `1.2.0.0/24` – `1.2.3.0/24` (`vpc-on-prem`)<br>• `1.2.4.0/24` – `1.2.7.0/24` (`vpc-p-svpc-app-01`)<br>• `1.2.8.0/24` – `1.2.11.0/24` (`vpc-p-svpc-app-02`) | `vpc-on-prem`, `vpc-p-svpc-app-01`, `vpc-p-svpc-app-02` | Privately Used Public IP (`pupi`) subnets (controlled by `enable_*_pupi`) for testing private non-RFC 1918 traffic flows across VPCs and hybrid links. |
| **`169.254.0.0/16`** | RFC 3927 (Link-Local) | `169.254.0.0/30` – `169.254.7.0/30` | `vpc-on-prem`, `vpc-p-transit`, `vpc-p-services` | `/30` point-to-point BGP peering addresses across the 16 HA VPN tunnels. |

#### 2. Subnet Naming Convention & When to Use What

Subnets follow the naming pattern:

```text
snet-<vpc>-p-<region>-[address_type]-<role>
```

*   **`<vpc>`**: Short VPC identifier (`onprem`, `transit`, `services`, `app1`, `app2`, `app3`).
*   **`p`**: Environment tier (`p` = production).
*   **`<region>`**: Short region code (`use4` = `us-east4`, `usw1` = `us-west1`).
*   **`[address_type]`** *(optional)*: Omitted for standard RFC 1918 subnets; `cgn` for RFC 6598 (`100.64.x.x`) subnets; `pupi` for Privately Used Public IP (`1.2.x.x`) subnets.
*   **`<role>`**: Defines what resources belong in the subnet:

| Subnet Suffix (`<role>`) | Subnet `purpose` | Private Google Access | When to Use / What to Deploy Here |
| :--- | :--- | :--- | :--- |
| **`client`** | `PRIVATE` (Standard) | `true` | Deploy **client / caller test VMs** (tagged with `[prefix]-workload = <env>-client`) that initiate traffic to web backends, Internal Load Balancers, or PSC endpoints. |
| **`web`** | `PRIVATE` (Standard) | `true` | Deploy **application backend VMs, Managed Instance Groups (MIGs), or GKE nodes** (tagged with `[prefix]-workload = <env>-webserver`) that serve requests directly or sit behind load balancers. |
| **`std`** | `PRIVATE` (Standard) | `true` | General-purpose **standard VM subnet** in single-tier VPCs (`vpc-p-transit`, `vpc-p-services`, `vpc-p-svpc-app-03`) for NVA appliances, shared infrastructure services, or general workloads. |
| **`psc-ep`** | `PRIVATE` (Standard) | `true` | Reserve for **Private Service Connect (PSC) Consumer Endpoints** (forwarding rules targeting a producer service attachment or Google APIs), keeping consumer endpoint IPs separate from VM NICs. |
| **`r-proxy`** | `REGIONAL_MANAGED_PROXY` (`role = "ACTIVE"`) | `false` *(GCP restriction)* | **Do not deploy VMs here.** Google Cloud automatically allocates source IPs from this proxy-only subnet for Regional Application Load Balancers, Regional Internal Proxy NLBs, and Secure Web Proxy in that VPC and region. |
| **`psc-nat`** | `PRIVATE_SERVICE_CONNECT` | `false` *(GCP restriction)* | **Do not deploy VMs here.** Attach this subnet to a `google_compute_service_attachment` when publishing a Private Service Connect **producer** service in `vpc-p-transit` so consumer traffic is SNATed to this range. |

### On-Prem VPC & Subnets (`vpcs.tf`)

> **VPC & Subnet Defaults (`vpcs.tf`)**:
> * **Private Google Access**: Automatically set to `"true"` in `module "subnets"` for all standard subnets (`purpose == null`), and `"false"` for `REGIONAL_MANAGED_PROXY` and `PRIVATE_SERVICE_CONNECT` subnets (which do not support Private Google Access in GCP).
> * **Firewall Policy Enforcement Order**: Each VPC in `local.vpcs` sets `firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"` (can be changed per VPC to `"AFTER_CLASSIC_FIREWALL"`).

**VPC**: `vpc-on-prem` (Project: `prj-[prefix]-on-prem`)

| Subnet Name | Region | CIDR Range | Type / Feature Flag |
| :--- | :--- | :--- | :--- |
| `snet-onprem-p-use4-client` | `us-east4` | `192.168.0.0/24` | Base |
| `snet-onprem-p-use4-web` | `us-east4` | `192.168.1.0/24` | Base |
| `snet-onprem-p-usw1-client` | `us-west1` | `192.168.2.0/24` | Base |
| `snet-onprem-p-usw1-web` | `us-west1` | `192.168.3.0/24` | Base |
| `snet-onprem-p-use4-cgn-client` | `us-east4` | `100.64.0.0/24` | CGN (`enable_on_prem_cgn = true`) |
| `snet-onprem-p-use4-cgn-web` | `us-east4` | `100.64.1.0/24` | CGN (`enable_on_prem_cgn = true`) |
| `snet-onprem-p-usw1-cgn-client` | `us-west1` | `100.64.2.0/24` | CGN (`enable_on_prem_cgn = true`) |
| `snet-onprem-p-usw1-cgn-web` | `us-west1` | `100.64.3.0/24` | CGN (`enable_on_prem_cgn = true`) |
| `snet-onprem-p-use4-pupi-client` | `us-east4` | `1.2.0.0/24` | PUPI (`enable_on_prem_pupi = true`) |
| `snet-onprem-p-use4-pupi-web` | `us-east4` | `1.2.1.0/24` | PUPI (`enable_on_prem_pupi = true`) |
| `snet-onprem-p-usw1-pupi-client` | `us-west1` | `1.2.2.0/24` | PUPI (`enable_on_prem_pupi = true`) |
| `snet-onprem-p-usw1-pupi-web` | `us-west1` | `1.2.3.0/24` | PUPI (`enable_on_prem_pupi = true`) |

### Service Projects (`serviceprojects.tf`)

This file creates the application service projects and attaches them to the Production Shared VPC host project:

*   **Projects**:
    *   `prj-[prefix]-p-svc-app-01`: App 1 Service Project, placed in `fldr-[prefix]-p-application`.
    *   `prj-[prefix]-p-svc-app-02`: App 2 Service Project, placed in `fldr-[prefix]-p-application`.
*   **Host Project**: `prj-[prefix]-p-net-host`
*   **Activated APIs**: `compute.googleapis.com`, `networksecurity.googleapis.com`, `dns.googleapis.com`, `cloudresourcemanager.googleapis.com`

### Production VPCs (`vpcs.tf`)

#### 1. Transit & Services VPCs (`vpc-p-transit` & `vpc-p-services`)

| VPC Network | Project | Subnet Name | Region | CIDR Range | Purpose / Type |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `snet-transit-p-use4-std` | `us-east4` | `10.10.0.0/24` | Standard |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `snet-transit-p-use4-r-proxy` | `us-east4` | `172.16.0.0/24` | Proxy-only (`REGIONAL_MANAGED_PROXY`) |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `snet-transit-p-use4-psc-nat` | `us-east4` | `172.16.1.0/24` | PSC NAT (`PRIVATE_SERVICE_CONNECT`) |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `snet-transit-p-usw1-std` | `us-west1` | `10.10.1.0/24` | Standard |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `snet-transit-p-usw1-r-proxy` | `us-west1` | `172.16.2.0/24` | Proxy-only (`REGIONAL_MANAGED_PROXY`) |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `snet-transit-p-usw1-psc-nat` | `us-west1` | `172.16.3.0/24` | PSC NAT (`PRIVATE_SERVICE_CONNECT`) |
| `vpc-p-services` | `prj-[prefix]-p-net-host` | `snet-services-p-use4-std` | `us-east4` | `10.11.0.0/24` | Standard |
| `vpc-p-services` | `prj-[prefix]-p-net-host` | `snet-services-p-usw1-std` | `us-west1` | `10.11.1.0/24` | Standard |

#### 2. Shared VPC App 1 (`vpc-p-svpc-app-01` in `prj-[prefix]-p-net-host`)

| Subnet Name | Region | CIDR Range | Type / Feature Flag |
| :--- | :--- | :--- | :--- |
| `snet-app1-p-use4-client` | `us-east4` | `10.12.0.0/24` | Base |
| `snet-app1-p-use4-web` | `us-east4` | `10.12.1.0/24` | Base |
| `snet-app1-p-use4-psc-ep` | `us-east4` | `10.12.2.0/24` | Base (PSC Endpoints) |
| `snet-app1-p-usw1-client` | `us-west1` | `10.12.3.0/24` | Base |
| `snet-app1-p-usw1-web` | `us-west1` | `10.12.4.0/24` | Base |
| `snet-app1-p-usw1-psc-ep` | `us-west1` | `10.12.5.0/24` | Base (PSC Endpoints) |
| `snet-app1-p-use4-cgn-client` | `us-east4` | `100.64.4.0/24` | CGN (`enable_prod_app1_cgn = true`) |
| `snet-app1-p-use4-cgn-web` | `us-east4` | `100.64.5.0/24` | CGN (`enable_prod_app1_cgn = true`) |
| `snet-app1-p-usw1-cgn-client` | `us-west1` | `100.64.6.0/24` | CGN (`enable_prod_app1_cgn = true`) |
| `snet-app1-p-usw1-cgn-web` | `us-west1` | `100.64.7.0/24` | CGN (`enable_prod_app1_cgn = true`) |
| `snet-app1-p-use4-pupi-client` | `us-east4` | `1.2.4.0/24` | PUPI (`enable_prod_app1_pupi = true`) |
| `snet-app1-p-use4-pupi-web` | `us-east4` | `1.2.5.0/24` | PUPI (`enable_prod_app1_pupi = true`) |
| `snet-app1-p-usw1-pupi-client` | `us-west1` | `1.2.6.0/24` | PUPI (`enable_prod_app1_pupi = true`) |
| `snet-app1-p-usw1-pupi-web` | `us-west1` | `1.2.7.0/24` | PUPI (`enable_prod_app1_pupi = true`) |

#### 3. Shared VPC App 2 (`vpc-p-svpc-app-02` in `prj-[prefix]-p-net-host`)

| Subnet Name | Region | CIDR Range | Type / Feature Flag |
| :--- | :--- | :--- | :--- |
| `snet-app2-p-use4-client` | `us-east4` | `10.13.0.0/24` | Base |
| `snet-app2-p-use4-web` | `us-east4` | `10.13.1.0/24` | Base |
| `snet-app2-p-use4-psc-ep` | `us-east4` | `10.13.2.0/24` | Base (PSC Endpoints) |
| `snet-app2-p-use4-r-proxy` | `us-east4` | `172.17.0.0/24` | Proxy-only (`REGIONAL_MANAGED_PROXY`) |
| `snet-app2-p-usw1-client` | `us-west1` | `10.13.3.0/24` | Base |
| `snet-app2-p-usw1-web` | `us-west1` | `10.13.4.0/24` | Base |
| `snet-app2-p-usw1-psc-ep` | `us-west1` | `10.13.5.0/24` | Base (PSC Endpoints) |
| `snet-app2-p-usw1-r-proxy` | `us-west1` | `172.17.1.0/24` | Proxy-only (`REGIONAL_MANAGED_PROXY`) |
| `snet-app2-p-use4-cgn-client` | `us-east4` | `100.64.8.0/24` | CGN (`enable_prod_app2_cgn = true`) |
| `snet-app2-p-use4-cgn-web` | `us-east4` | `100.64.9.0/24` | CGN (`enable_prod_app2_cgn = true`) |
| `snet-app2-p-usw1-cgn-client` | `us-west1` | `100.64.10.0/24` | CGN (`enable_prod_app2_cgn = true`) |
| `snet-app2-p-usw1-cgn-web` | `us-west1` | `100.64.11.0/24` | CGN (`enable_prod_app2_cgn = true`) |
| `snet-app2-p-use4-pupi-client` | `us-east4` | `1.2.8.0/24` | PUPI (`enable_prod_app2_pupi = true`) |
| `snet-app2-p-use4-pupi-web` | `us-east4` | `1.2.9.0/24` | PUPI (`enable_prod_app2_pupi = true`) |
| `snet-app2-p-usw1-pupi-client` | `us-west1` | `1.2.10.0/24` | PUPI (`enable_prod_app2_pupi = true`) |
| `snet-app2-p-usw1-pupi-web` | `us-west1` | `1.2.11.0/24` | PUPI (`enable_prod_app2_pupi = true`) |

#### 4. Shared VPC App 3 (`vpc-p-svpc-app-03` in `prj-[prefix]-p-net-host`)

| Subnet Name | Region | CIDR Range | Type / Feature Flag |
| :--- | :--- | :--- | :--- |
| `snet-app3-p-use4-std` | `us-east4` | `10.14.0.0/24` | Base |
| `snet-app3-p-usw1-std` | `us-west1` | `10.14.1.0/24` | Base |

### Cloud NAT & NAT Routers (`nat.tf`)

Following Google Cloud best practices, Cloud NAT gateways are provisioned on dedicated regional Cloud Routers (separate from the HA VPN BGP Cloud Routers) for every VPC with subnets across each active subnet region (`us-east4` and `us-west1`):

| VPC Network | Project | NAT Cloud Router Name | NAT Gateway Name | Settings |
| :--- | :--- | :--- | :--- | :--- |
| `vpc-on-prem` | `prj-[prefix]-on-prem` | `vpc-on-prem-nat-cr-<region>` | `vpc-on-prem-nat-<region>` | `ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging |
| `vpc-p-transit` | `prj-[prefix]-p-net-transit` | `vpc-p-transit-nat-cr-<region>` | `vpc-p-transit-nat-<region>` | `ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging |
| `vpc-p-services` | `prj-[prefix]-p-net-host` | `vpc-p-services-nat-cr-<region>` | `vpc-p-services-nat-<region>` | `ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging |
| `vpc-p-svpc-app-01` | `prj-[prefix]-p-net-host` | `vpc-p-svpc-app-01-nat-cr-<region>` | `vpc-p-svpc-app-01-nat-<region>` | `ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging |
| `vpc-p-svpc-app-02` | `prj-[prefix]-p-net-host` | `vpc-p-svpc-app-02-nat-cr-<region>` | `vpc-p-svpc-app-02-nat-<region>` | `ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging |
| `vpc-p-svpc-app-03` | `prj-[prefix]-p-net-host` | `vpc-p-svpc-app-03-nat-cr-<region>` | `vpc-p-svpc-app-03-nat-<region>` | `ALL_SUBNETWORKS_ALL_IP_RANGES`, `min_ports_per_vm = 4096`, `ERRORS_ONLY` logging |

### VPNs (`vpn.tf`)

This file sets up redundant HA VPN gateways, tunnels, and BGP sessions between the `on-prem`, `production transit`, and `production services` environments.

#### 1. On-Prem (`vpc-on-prem`, ASN `65001`) ↔ Production Transit (`vpc-p-transit`, ASN `65002`)

| Region | HA VPN Gateway | Cloud Router (ASN) | VPN Tunnel Name | BGP Session IP |
| :--- | :--- | :--- | :--- | :--- |
| `us-east4` | `gw-on-prem-use4` | `router-vpn-on-prem-use4` (`65001`) | `tunnel-on-prem-to-transit-use4-if0`<br>`tunnel-on-prem-to-transit-use4-if1` | `169.254.0.2/30`<br>`169.254.1.2/30` |
| `us-east4` | `gw-p-transit-use4` | `router-vpn-p-transit-use4` (`65002`) | `tunnel-transit-to-on-prem-use4-if0`<br>`tunnel-transit-to-on-prem-use4-if1` | `169.254.0.1/30`<br>`169.254.1.1/30` |
| `us-west1` | `gw-on-prem-usw1` | `router-vpn-on-prem-usw1` (`65001`) | `tunnel-on-prem-to-transit-usw1-if0`<br>`tunnel-on-prem-to-transit-usw1-if1` | `169.254.2.2/30`<br>`169.254.3.2/30` |
| `us-west1` | `gw-p-transit-usw1` | `router-vpn-p-transit-usw1` (`65002`) | `tunnel-transit-to-on-prem-usw1-if0`<br>`tunnel-transit-to-on-prem-usw1-if1` | `169.254.2.1/30`<br>`169.254.3.1/30` |

#### 2. Production Transit (`vpc-p-transit`, ASN `65002`) ↔ Production Services (`vpc-p-services`, ASN `65003`)

| Region | HA VPN Gateway | Cloud Router (ASN) | VPN Tunnel Name | BGP Session IP |
| :--- | :--- | :--- | :--- | :--- |
| `us-east4` | `gw-p-transit-to-svcs-use4` | `router-vpn-p-transit-use4` (`65002`) | `tunnel-transit-to-svcs-use4-if0`<br>`tunnel-transit-to-svcs-use4-if1` | `169.254.4.1/30`<br>`169.254.5.1/30` |
| `us-east4` | `gw-p-svcs-to-transit-use4` | `router-vpn-p-svcs-use4` (`65003`) | `tunnel-svcs-to-transit-use4-if0`<br>`tunnel-svcs-to-transit-use4-if1` | `169.254.4.2/30`<br>`169.254.5.2/30` |
| `us-west1` | `gw-p-transit-to-svcs-usw1` | `router-vpn-p-transit-usw1` (`65002`) | `tunnel-transit-to-svcs-usw1-if0`<br>`tunnel-transit-to-svcs-usw1-if1` | `169.254.6.1/30`<br>`169.254.7.1/30` |
| `us-west1` | `gw-p-svcs-to-transit-usw1` | `router-vpn-p-svcs-usw1` (`65003`) | `tunnel-svcs-to-transit-usw1-if0`<br>`tunnel-svcs-to-transit-usw1-if1` | `169.254.6.2/30`<br>`169.254.7.2/30` |

### Network Connectivity Center (`ncc.tf`)

When `var.enable_ncc = true` (`default = false` in the module, `enable_ncc = true` in `examples/ncc`), this file configures the Network Connectivity Center hub and spokes:

*   **Hub**:
    *   **Name**: `ncc-hub-prod`
    *   **Project**: `prj-[prefix]-p-net-transit`
    *   **Topology & Routing**: `MESH` preset topology (`PRESET` policy mode) with Private Service Connect propagation enabled (`export_psc = true`).
    *   **Default Group Auto-Accept**: Automatically accepts spokes from `prj-[prefix]-p-net-host` and `prj-[prefix]-p-net-transit`.
*   **Spokes**:
    *   **Hybrid Spokes (VPN)** (created in `prj-[prefix]-p-net-transit` with `site_to_site_data_transfer = true` and `include_import_ranges = ["ALL_IPV4_RANGES"]`):
        *   `spoke-p-hybrid-vpn-onprem-use4`: Connects on-prem VPN tunnels in `us-east4`.
        *   `spoke-p-hybrid-vpn-onprem-usw1`: Connects on-prem VPN tunnels in `us-west1`.
        *   `spoke-p-hybrid-vpn-svcs-use4`: Connects services VPN tunnels in `us-east4`.
        *   `spoke-p-hybrid-vpn-svcs-usw1`: Connects services VPN tunnels in `us-west1`.
    *   **VPC Spokes**:
        *   `spoke-p-vpc-transit` (in `prj-[prefix]-p-net-transit`): Connects `vpc-p-transit`.
        *   `spoke-p-vpc-app1` (in `prj-[prefix]-p-net-host`): Connects `vpc-p-svpc-app-01`.
        *   `spoke-p-vpc-app2` (in `prj-[prefix]-p-net-host`): Connects `vpc-p-svpc-app-02`.
        *   `spoke-p-vpc-app3` (in `prj-[prefix]-p-net-host`): Connects `vpc-p-svpc-app-03`.

### VPC Network Peering (`vpc-peering.tf`)

When `var.enable_vpc_peering = true` and `var.enable_ncc = false` (enforced via variable validation and resource preconditions so both cannot be `true` simultaneously), this file provisions bidirectional hub-and-spoke VPC Network Peerings between `vpc-p-transit` and the application VPCs with custom route exchange (`export_custom_routes = true`, `import_custom_routes = true`) enabled:

| Peering Key | Transit-to-Spoke Peering (`vpc-p-transit`) | Spoke-to-Transit Peering | Spoke VPC Network | Custom Routes (`export` / `import`) |
| :--- | :--- | :--- | :--- | :--- |
| `app1` | `peer-p-transit-to-app1` | `peer-p-app1-to-transit` | `vpc-p-svpc-app-01` | `true` / `true` |
| `app2` | `peer-p-transit-to-app2` | `peer-p-app2-to-transit` | `vpc-p-svpc-app-02` | `true` / `true` |
| `app3` | `peer-p-transit-to-app3` | `peer-p-app3-to-transit` | `vpc-p-svpc-app-03` | `true` / `true` |

### Firewall Policies & Secure Tags (`firewalls.tf`)

This file provisions organization-scoped `GCE_FIREWALL` Secure Tags, a folder-level Hierarchical Firewall Policy on `fldr-[prefix]-network-lab`, and a Global Network Firewall Policy for each of the 6 VPC networks.

#### 1. Firewall Secure Tags (`GCE_FIREWALL`)

Both tag keys are created at the organization level with `purpose = "GCE_FIREWALL"` and `purpose_data = { organization = "auto" }` so tag values can be referenced across both the Hierarchical Firewall Policy and multi-VPC Global Network Firewall Policies (and so a VM can hold both a workload role tag and the `quarantine` tag simultaneously):

| Tag Key (`short_name`) | Tag Value (`short_name`) | Purpose |
| :--- | :--- | :--- |
| `[prefix]-quarantine` | `quarantine` | Isolates compromised or quarantined VMs by denying all ingress (`500`) and egress (`501`) at the Hierarchical Firewall Policy layer. |
| `[prefix]-workload` | `on-prem-webserver`, `on-prem-client`, `app1-webserver`, `app1-client`, `app2-webserver`, `app2-client`, `app3-webserver`, `app3-client` | Identifies client and webserver tiers across `on-prem`, `app1`, `app2`, and `app3` VPCs for tag-based firewall rules. |

#### 2. Hierarchical Firewall Policy (`hfwp-[prefix]-network-lab`)

Created under and associated with the Level 1 base folder (`fldr-[prefix]-network-lab`):

| Priority | Direction | Target | Source | Destination | Protocol / Port | Action | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **500** | `INGRESS` | `SecureTag:quarantine` | `0.0.0.0/0` | Any | `all` | `deny` | Deny all ingress to a compute resource assigned the `quarantine` secure tag. |
| **501** | `EGRESS` | `SecureTag:quarantine` | Any | `0.0.0.0/0` | `all` | `deny` | Deny all egress from a compute resource assigned the `quarantine` secure tag. |
| **1000** | `INGRESS` | `ALL` | `35.191.0.0/16`, `130.211.0.0/22` | Any | `all` | `allow` | Allow ingress from Google Load Balancer proxy/health check IPs. |
| **2000** | `INGRESS` | `ALL` | `35.191.0.0/16`, `209.85.152.0/22`, `209.85.204.0/22` | Any | `all` | `allow` | Allow ingress from regional external passthrough NLB health check/proxy IPs. |
| **3000** | `INGRESS` | `ALL` | `35.235.240.0/20` | Any | `tcp:22,3389` | `allow` | Allow SSH (`22`) and RDP (`3389`) ingress from Identity-Aware Proxy (IAP). |
| **3100** | `INGRESS` | `ALL` | `src_region_codes`: `["CU", "IR", "KP", "SY"]` | Any | `all` | `deny` | Deny ingress requests from embargoed geo-locations. |
| **3200** | `INGRESS` | `ALL` | `src_threat_intelligences`: `["iplist-known-malicious-ips", "iplist-tor-exit-nodes"]` | Any | `all` | `deny` | Deny ingress requests from known malicious IPs and TOR exit nodes. |
| **3300** | `EGRESS` | `ALL` | Any | `dest_region_codes`: `["CU", "IR", "KP", "SY"]` | `all` | `deny` | Deny egress requests to embargoed geo-locations. |
| **3400** | `EGRESS` | `ALL` | Any | `dest_threat_intelligences`: `["iplist-known-malicious-ips", "iplist-tor-exit-nodes"]` | `all` | `deny` | Deny egress requests to known malicious IPs and TOR exit nodes. |

#### 3. Per-VPC Global Network Firewall Policies (`gfwp-<vpc_name>`)

Each VPC in `local.vpcs` is associated with its own Global Network Firewall Policy in its respective project and configured with `firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"` in `vpcs.tf` so that Global Network Firewall Policies are evaluated before Classic VPC Firewall Rules (this can be flipped per VPC to `"AFTER_CLASSIC_FIREWALL"` in `local.vpcs`):

| Policy Name | VPC Network | Priority | Direction | Target | Source / Destination | Protocol / Port | Action | Logging | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `gfwp-vpc-on-prem` | `vpc-on-prem` | **5000** | `INGRESS` | `SecureTag:on-prem-webserver` | Source: `SecureTag:on-prem-client`, `app1-client`, `app2-client`, `app3-client` | `all` | `allow` | `false` | Allow ingress to on-prem webserver from on-prem, app1, app2, and app3 clients. |
| `gfwp-vpc-p-transit` | `vpc-p-transit` | **10000** | `INGRESS` | `ALL` | Source: `172.16.0.0/24`, `172.16.2.0/24` | `all` | `allow` | `false` | Allow ingress from regional managed proxy-only subnets. |
| `gfwp-vpc-p-transit` | `vpc-p-transit` | **20000** | `INGRESS` | `ALL` | Source: `172.16.1.0/24`, `172.16.3.0/24` | `all` | `allow` | `false` | Allow ingress from PSC NAT subnets. |
| `gfwp-vpc-p-transit` | `vpc-p-transit` | **2000000000** | `INGRESS` | `ALL` | Source: `0.0.0.0/0` | `all` | `deny` | `true` | Explicit DENY ingress rule with logging enabled. |
| `gfwp-vpc-p-services` | `vpc-p-services` | *(None)* | — | — | — | — | — | — | Associated policy with empty rule set (`{}`). |
| `gfwp-vpc-p-svpc-app-01` | `vpc-p-svpc-app-01` | **30000** | `INGRESS` | `SecureTag:app1-webserver` | Source: `SecureTag:app1-client`, `app2-client`, `on-prem-client` | `all` | `allow` | `false` | Allow ingress to app1 webserver from app1, app2, and on-prem clients. |
| `gfwp-vpc-p-svpc-app-01` | `vpc-p-svpc-app-01` | **2000000000** | `INGRESS` | `ALL` | Source: `0.0.0.0/0` | `all` | `deny` | `true` | Explicit DENY ingress rule with logging enabled. |
| `gfwp-vpc-p-svpc-app-02` | `vpc-p-svpc-app-02` | **60000** | `INGRESS` | `ALL` | Source: `172.17.0.0/24`, `172.17.1.0/24` | `all` | `allow` | `false` | Allow ingress from regional managed proxy-only subnets. |
| `gfwp-vpc-p-svpc-app-02` | `vpc-p-svpc-app-02` | **70000** | `INGRESS` | `SecureTag:app2-webserver` | Source: `SecureTag:app2-client`, `app1-client`, `on-prem-client` | `all` | `allow` | `false` | Allow ingress to app2 webserver from app2, app1, and on-prem clients. |
| `gfwp-vpc-p-svpc-app-02` | `vpc-p-svpc-app-02` | **2000000000** | `INGRESS` | `ALL` | Source: `0.0.0.0/0` | `all` | `deny` | `true` | Explicit DENY ingress rule with logging enabled. |
| `gfwp-vpc-p-svpc-app-03` | `vpc-p-svpc-app-03` | **90000** | `INGRESS` | `SecureTag:app3-webserver` | Source: `SecureTag:app3-client`, `on-prem-client` | `all` | `allow` | `false` | Allow ingress to app3 webserver from intra-VPC app3 and on-prem clients. |
| `gfwp-vpc-p-svpc-app-03` | `vpc-p-svpc-app-03` | **91000** | `EGRESS` | `ALL` | Dest: `local.app3_and_on_prem_cidrs` (`10.14.0.0/24`, `10.14.1.0/24`, and `on-prem` subnets) | `all` | `allow` | `false` | Allow egress within app3 VPC and to on-prem subnets only. |
| `gfwp-vpc-p-svpc-app-03` | `vpc-p-svpc-app-03` | **92000** | `EGRESS` | `ALL` | Dest: `local.internal_lab_cidrs` | `all` | `deny` | `true` | Isolate app3 in NCC mesh: deny egress to all other internal lab VPCs (`app1`, `app2`, `transit`, `services`) while keeping internet egress open via Cloud NAT. |
| `gfwp-vpc-p-svpc-app-03` | `vpc-p-svpc-app-03` | **2000000000** | `INGRESS` | `ALL` | Source: `0.0.0.0/0` | `all` | `deny` | `true` | Explicit DENY ingress rule with logging enabled. |


## Usage

```hcl
module "networking" {
  source = "../../../modules/networking/"

  organization_id    = var.organization_id
  billing_account_id = var.billing_account_id
  prefix             = var.prefix
  enable_ncc         = true
}
```

For complete end-to-end deployment templates (which are copied into `examples/<lab_name>` and configured with your remote GCS backend and `terraform.tfvars`), see **[examples/ncc/02-networking](../../examples/ncc/02-networking)**, **[examples/vpc-peering/02-networking](../../examples/vpc-peering/02-networking)**, and **[examples/ncc/README.md](../../examples/ncc/README.md)**.

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
| deletion\_protection | Whether to enable deletion protection on service projects. | `bool` | `false` | no |
| enable\_ncc | Whether to provision the Network Connectivity Center (NCC) hub and spokes. Cannot be true at the same time as enable\_vpc\_peering. | `bool` | `false` | no |
| enable\_on\_prem\_cgn | Enable CGN subnets for on-prem VPC. | `bool` | `true` | no |
| enable\_on\_prem\_pupi | Enable PUPI subnets for on-prem VPC. | `bool` | `true` | no |
| enable\_prod\_app1\_cgn | Enable CGN subnets for App 1 VPC. | `bool` | `true` | no |
| enable\_prod\_app1\_pupi | Enable PUPI subnets for App 1 VPC. | `bool` | `true` | no |
| enable\_prod\_app2\_cgn | Enable CGN subnets for App 2 VPC. | `bool` | `true` | no |
| enable\_prod\_app2\_pupi | Enable PUPI subnets for App 2 VPC. | `bool` | `true` | no |
| enable\_vpc\_peering | Whether to provision VPC Network Peering between the production transit VPC and application VPCs. Cannot be true at the same time as enable\_ncc. | `bool` | `false` | no |
| on\_prem\_base\_subnets | A list of base subnets for the on-prem VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "192.168.0.0/24",<br>    "subnet_name": "snet-onprem-p-use4-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "192.168.1.0/24",<br>    "subnet_name": "snet-onprem-p-use4-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "192.168.2.0/24",<br>    "subnet_name": "snet-onprem-p-usw1-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "192.168.3.0/24",<br>    "subnet_name": "snet-onprem-p-usw1-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| on\_prem\_cgn\_subnets | A list of CGN subnets for the on-prem VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "100.64.0.0/24",<br>    "subnet_name": "snet-onprem-p-use4-cgn-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "100.64.1.0/24",<br>    "subnet_name": "snet-onprem-p-use4-cgn-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "100.64.2.0/24",<br>    "subnet_name": "snet-onprem-p-usw1-cgn-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "100.64.3.0/24",<br>    "subnet_name": "snet-onprem-p-usw1-cgn-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| on\_prem\_pupi\_subnets | A list of PUPI subnets for the on-prem VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "1.2.0.0/24",<br>    "subnet_name": "snet-onprem-p-use4-pupi-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "1.2.1.0/24",<br>    "subnet_name": "snet-onprem-p-use4-pupi-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "1.2.2.0/24",<br>    "subnet_name": "snet-onprem-p-usw1-pupi-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "1.2.3.0/24",<br>    "subnet_name": "snet-onprem-p-usw1-pupi-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| organization\_id | The organization ID. | `string` | n/a | yes |
| prefix | Prefix for folders and projects. | `string` | `"lab"` | no |
| prod\_app1\_base\_subnets | A list of base subnets for the production App 1 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "10.12.0.0/24",<br>    "subnet_name": "snet-app1-p-use4-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.12.1.0/24",<br>    "subnet_name": "snet-app1-p-use4-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.12.2.0/24",<br>    "subnet_name": "snet-app1-p-use4-psc-ep",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.12.3.0/24",<br>    "subnet_name": "snet-app1-p-usw1-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "10.12.4.0/24",<br>    "subnet_name": "snet-app1-p-usw1-web",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "10.12.5.0/24",<br>    "subnet_name": "snet-app1-p-usw1-psc-ep",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_app1\_cgn\_subnets | A list of CGN subnets for the production App 1 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "100.64.4.0/24",<br>    "subnet_name": "snet-app1-p-use4-cgn-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "100.64.5.0/24",<br>    "subnet_name": "snet-app1-p-use4-cgn-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "100.64.6.0/24",<br>    "subnet_name": "snet-app1-p-usw1-cgn-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "100.64.7.0/24",<br>    "subnet_name": "snet-app1-p-usw1-cgn-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_app1\_pupi\_subnets | A list of PUPI subnets for the production App 1 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "1.2.4.0/24",<br>    "subnet_name": "snet-app1-p-use4-pupi-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "1.2.5.0/24",<br>    "subnet_name": "snet-app1-p-use4-pupi-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "1.2.6.0/24",<br>    "subnet_name": "snet-app1-p-usw1-pupi-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "1.2.7.0/24",<br>    "subnet_name": "snet-app1-p-usw1-pupi-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_app2\_base\_subnets | A list of base subnets for the production App 2 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>    purpose       = optional(string)<br>    role          = optional(string)<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "10.13.0.0/24",<br>    "subnet_name": "snet-app2-p-use4-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.13.1.0/24",<br>    "subnet_name": "snet-app2-p-use4-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.13.2.0/24",<br>    "subnet_name": "snet-app2-p-use4-psc-ep",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "purpose": "REGIONAL_MANAGED_PROXY",<br>    "role": "ACTIVE",<br>    "subnet_ip": "172.17.0.0/24",<br>    "subnet_name": "snet-app2-p-use4-r-proxy",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.13.3.0/24",<br>    "subnet_name": "snet-app2-p-usw1-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "10.13.4.0/24",<br>    "subnet_name": "snet-app2-p-usw1-web",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "10.13.5.0/24",<br>    "subnet_name": "snet-app2-p-usw1-psc-ep",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "purpose": "REGIONAL_MANAGED_PROXY",<br>    "role": "ACTIVE",<br>    "subnet_ip": "172.17.1.0/24",<br>    "subnet_name": "snet-app2-p-usw1-r-proxy",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_app2\_cgn\_subnets | A list of CGN subnets for the production App 2 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "100.64.8.0/24",<br>    "subnet_name": "snet-app2-p-use4-cgn-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "100.64.9.0/24",<br>    "subnet_name": "snet-app2-p-use4-cgn-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "100.64.10.0/24",<br>    "subnet_name": "snet-app2-p-usw1-cgn-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "100.64.11.0/24",<br>    "subnet_name": "snet-app2-p-usw1-cgn-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_app2\_pupi\_subnets | A list of PUPI subnets for the production App 2 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "1.2.8.0/24",<br>    "subnet_name": "snet-app2-p-use4-pupi-client",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "1.2.9.0/24",<br>    "subnet_name": "snet-app2-p-use4-pupi-web",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "1.2.10.0/24",<br>    "subnet_name": "snet-app2-p-usw1-pupi-client",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "subnet_ip": "1.2.11.0/24",<br>    "subnet_name": "snet-app2-p-usw1-pupi-web",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_app3\_base\_subnets | A list of base subnets for the production App 3 VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "10.14.0.0/24",<br>    "subnet_name": "snet-app3-p-use4-std",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.14.1.0/24",<br>    "subnet_name": "snet-app3-p-usw1-std",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_services\_vpc\_subnets | A list of subnets for the production services VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>    purpose       = optional(string)<br>    role          = optional(string)<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "10.11.0.0/24",<br>    "subnet_name": "snet-services-p-use4-std",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.11.1.0/24",<br>    "subnet_name": "snet-services-p-usw1-std",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| prod\_transit\_vpc\_subnets | A list of subnets for the production transit VPC. | <pre>list(object({<br>    subnet_name   = string<br>    subnet_ip     = string<br>    subnet_region = string<br>    purpose       = optional(string)<br>    role          = optional(string)<br>  }))</pre> | <pre>[<br>  {<br>    "subnet_ip": "10.10.0.0/24",<br>    "subnet_name": "snet-transit-p-use4-std",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "purpose": "REGIONAL_MANAGED_PROXY",<br>    "role": "ACTIVE",<br>    "subnet_ip": "172.16.0.0/24",<br>    "subnet_name": "snet-transit-p-use4-r-proxy",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "purpose": "PRIVATE_SERVICE_CONNECT",<br>    "subnet_ip": "172.16.1.0/24",<br>    "subnet_name": "snet-transit-p-use4-psc-nat",<br>    "subnet_region": "us-east4"<br>  },<br>  {<br>    "subnet_ip": "10.10.1.0/24",<br>    "subnet_name": "snet-transit-p-usw1-std",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "purpose": "REGIONAL_MANAGED_PROXY",<br>    "role": "ACTIVE",<br>    "subnet_ip": "172.16.2.0/24",<br>    "subnet_name": "snet-transit-p-usw1-r-proxy",<br>    "subnet_region": "us-west1"<br>  },<br>  {<br>    "purpose": "PRIVATE_SERVICE_CONNECT",<br>    "subnet_ip": "172.16.3.0/24",<br>    "subnet_name": "snet-transit-p-usw1-psc-nat",<br>    "subnet_region": "us-west1"<br>  }<br>]</pre> | no |
| regions | Primary and secondary regions for lab deployment. | <pre>object({<br>    primary   = string<br>    secondary = string<br>  })</pre> | <pre>{<br>  "primary": "us-east4",<br>  "secondary": "us-west1"<br>}</pre> | no |
| vpc\_mtu | Maximum Transmission Unit (MTU) in bytes for all provisioned VPC networks. | `number` | `1500` | no |

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
