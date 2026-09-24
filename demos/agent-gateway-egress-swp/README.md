# CUJ 2 — Agent Gateway: Public Egress via Secure Web Proxy + Cloud NAT Static IP

This demo shows how to govern all public-internet egress from a Vertex AI Agent
Runtime (Reasoning Engine) so that:

1. Every outbound connection from the agent exits **through the customer VPC**
   via the **Agent Gateway** (AGENT_TO_ANYWHERE mode, PSC-Interface).
2. That VPC-bound traffic is steered through a **customer-deployed Secure Web
   Proxy (SWP) in next-hop mode** for Layer-7 inspection and policy enforcement.
3. The SWP forwards to **Cloud NAT with a reserved static external IP**, giving
   the agent a predictable, allowlistable egress identity.

The agent (a software bug-triage assistant) reaches a public, no-auth **MCP
server on Cloud Run** to read bug tickets. The Cloud Run service sees the
agent's traffic arriving from the static NAT IP, which you can confirm in its
request logs.

---

## Architecture

### Traffic Path

The demo has **two distinct egress paths** from the Reasoning Engine:

```
┌──────────────────────────────────────────────────────────────────────┐
│  Google-managed (Vertex AI)                                          │
│                                                                      │
│   Reasoning Engine (Agent Runtime)                                   │
│     └─ agent_gateway_config bound → Agent Gateway (AGENT_TO_ANYWHERE)│
│                                      └─ AgentConnectivityTemplate    │
│                                         (VPC_EGRESS_MODE_ALL_TRAFFIC)│
└──────────────────────────────────────────────────────────────────────┘
                              │ PSC-Interface network attachment
                              │ (All traffic including DNS is forwarded)
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Customer VPC                                                        │
│                                                                      │
│   [Agent Gateway subnet 10.20.0.0/26]  (Private Google Access ON)    │
│          │                                                           │
│   ┌──────┴──────────────────┐                                        │
│   │ VPC Cloud DNS           │                                        │
│   │                         │                                        │
│   │ *.googleapis.com        │ all other traffic (*.run.app, etc.)    │
│   │ → DNS: 199.36.153.8/30  │ → DNS: public IP                       │
│   │                         │                                        │
│   │ PBR 1500: bypass SWP    │ PBR 2000: redirect to SWP              │
│   │ DEFAULT_ROUTING         │ next_hop_ilb_ip = SWP internal IP      │
│   │        │                │        │                               │
│   │        ▼                │        ▼                               │
│   │ Private Google Access   │ Secure Web Proxy (NEXT_HOP_MODE)       │
│   │ (internal, no NAT)      │   • ALLOW policy (no TLS inspection)   │
│   │        │                │   • Anti-loop PBR (priority 1000)      │
│   │        ▼                │        │                               │
│   │ Google APIs ✓           │        ▼                               │
│   │ (telemetry, Vertex AI,  │ Cloud Router → Cloud NAT               │
│   │  model endpoint, etc.)  │   • MANUAL_ONLY · static external IP   │
│   │                         │        │                               │
│   └─────────────────────────┘        │ Public internet               │
│                                      ▼                               │
└──────────────────────────── bug-tickets-mcp (Cloud Run) ─────────────┘
                                INGRESS_TRAFFIC_ALL · no IAM gate
                                (sees the static NAT IP as source)
```

> **Why two paths?** When a Reasoning Engine is bound to an Agent Gateway with an
> `AgentConnectivityTemplate` using `VPC_EGRESS_MODE_ALL_TRAFFIC`, ALL its outbound
> traffic (including DNS requests) natively enters the customer VPC via PSC-I. Internal Google API
> endpoints (`*.mtls.googleapis.com`, Vertex AI, Cloud Trace, etc.) can only
> be reached from within Google's infrastructure — routing them through Cloud NAT
> (a public IP) causes SSL handshake failures. The DNS override within the VPC + PBR bypass
> routes Google API traffic via **Private Google Access** (internal, no NAT),
> while all other internet traffic (the MCP server) still goes through the
> SWP → Cloud NAT path where the static IP is enforced.

### Layer-by-Layer Reference Table

| Layer | What it does | Terraform resource |
|---|---|---|
| **Agent Runtime** | Hosts the ADK-based software-bug-agent; all connections egress through the Agent Gateway | `google_vertex_ai_reasoning_engine` in `modules/agent-engine/main.tf` |
| **Agent Gateway binding** | `agent_gateway_config.agent_to_anywhere_config.agent_gateway` routes ALL engine egress through the customer VPC | same resource, `agent_gateway_config` block |
| **PSC-Interface** | Dedicated network attachment connecting Agent Runtime to the customer VPC | `google_compute_network_attachment` in `modules/agent-gateway/main.tf` |
| **Agent Gateway** | `AGENT_TO_ANYWHERE` gateway terminates PSC-I and injects traffic into the Agent Gateway subnet | `terraform_data.agent_gateway` in `modules/agent-gateway/main.tf` |
| **Agent Gateway Authz Policy** | Overrides the gateway's internal default-deny behavior and allows all traffic to flow to the customer VPC | `terraform_data.agent_gateway` in `modules/agent-gateway/main.tf` |
| **Agent Registry Endpoints** | Registers Google APIs and the MCP server, enabling the Gateway to build its dynamic routing table | `module.agent_registry_endpoints` in `terraform/main.tf` |
| **Agent Connectivity Template** | Forces all traffic (including DNS) from the Reasoning Engine to exit through the VPC via `ALL_TRAFFIC` mode | API scripts triggered by `terraform_data` in `modules/agent-gateway/main.tf` |
| **Private Google Access** | Enabled on the Agent Gateway subnet so Google API traffic can exit internally without NAT | `private_ip_google_access = true` on `google_compute_subnetwork.agent_gateway` in `modules/networking/main.tf` |
| **DNS override (googleapis)** | Private Cloud DNS zones natively intercept and redirect `*.googleapis.com` to the `private.googleapis.com` VIP (`199.36.153.8/30`) | `google_dns_managed_zone.googleapis` in `modules/networking/main.tf` |
| **Policy-Based Route (googleapis bypass)** | Priority 1500 — lets traffic destined for `199.36.153.8/30` take the default route (Private Google Access), bypassing the SWP | `google_network_connectivity_policy_based_route.googleapis_restricted_bypass` in `modules/secure-web-proxy/main.tf` |
| **Policy-Based Route (forced SWP)** | Priority 2000 — redirects all remaining Agent Gateway subnet egress (src `10.20.0.0/26`, dst `0.0.0.0/0`) to the SWP gateway IP | `google_network_connectivity_policy_based_route.agw_to_swp` in `modules/secure-web-proxy/main.tf` |
| **Policy-Based Route (anti-loop)** | Priority 1000 — prevents SWP's own proxy-originated connections from looping back through the SWP | `google_network_connectivity_policy_based_route.swp_anti_loop` in `modules/secure-web-proxy/main.tf` |
| **Secure Web Proxy** | L7 proxy in `NEXT_HOP_ROUTING_MODE`; applies `ALLOW` security policy; forwards traffic to the default internet route | `google_network_services_gateway` in `modules/secure-web-proxy/main.tf` |
| **Cloud NAT** | SNAT with a single reserved static external IP; the MCP server sees this IP | `google_compute_router_nat` + `google_compute_address.nat` in `modules/networking/main.tf` |
| **bug-tickets-mcp** | Public Cloud Run service (`INGRESS_TRAFFIC_ALL`); no IAP or auth; logs the caller's IP in `X-Forwarded-For` | `modules/mcp-cloud-run` + `images.tf` (Cloud Build from source) |

---

## Differences from `demos/agent-gateway`

| Feature | `demos/agent-gateway` (CUJ1) | This demo (CUJ2) |
|---|---|---|
| Focus | **Ingress** governance (IAP, Model Armor) | **Egress** governance (SWP, Cloud NAT static IP) |
| MCP server | Internal (private Cloud Run, IAP-gated) | Public (no-auth Cloud Run, `*.run.app`) |
| SWP | None | Customer-deployed, next-hop mode |
| Cloud NAT | AUTO_ONLY | MANUAL_ONLY with reserved static IP |
| Authz extensions | IAP + Model Armor | None (scope: network egress only) |

---

## Prerequisites

- A GCP project with billing enabled.
- Your account must have `roles/owner` or equivalent (`roles/editor` +
  `roles/iam.securityAdmin` + `roles/resourcemanager.projectIamAdmin` +
  `roles/cloudbuild.builds.editor` + `roles/serviceusage.serviceUsageConsumer`).
  - *Note on Cloud Build:* `roles/editor` does not grant permissions to create Cloud Build jobs. If you are not a Project Owner, run:
    ```bash
    export PROJECT_ID=YOUR_PROJECT_ID
    export USER_EMAIL=$(gcloud config get-value account)

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="user:$USER_EMAIL" \
      --role="roles/cloudbuild.builds.editor"

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="user:$USER_EMAIL" \
      --role="roles/serviceusage.serviceUsageConsumer"
    ```
    *(Alternatively, add your account to `platform_admin_members = ["user:you@example.com"]` in `terraform.tfvars`, and Terraform will manage these grants automatically.)*
- Tools: `gcloud` (authenticated), `terraform >= 1.5`, `uv` (Python package manager).
- The project must be under a GCP **organization** (required for Agent Identity
  IAM principal sets).
- **Bootstrap APIs:** In a new GCP project, the Cloud Resource Manager and Service Usage APIs must be enabled via `gcloud` before Terraform can read project metadata or manage services.

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

---

## Deploy Walkthrough

### Step 0 — Clone and navigate

```bash
cd cloud-networking-solutions/demos/agent-gateway-egress-swp/terraform
```

### Step 1 — Enable Bootstrap APIs

In a new project, enable the foundational APIs required by Terraform and Cloud Storage:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=us-central1

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  dns.googleapis.com \
  agentregistry.googleapis.com \
  networkservices.googleapis.com \
  networksecurity.googleapis.com \
  networkconnectivity.googleapis.com \
  --project="${PROJECT_ID}"
```

### Step 2 — Create the Terraform state bucket

```bash
gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" \
  --location="${REGION}" \
  --uniform-bucket-level-access
```

### Step 3 — Configure Terraform

```bash
cp example.backend.conf backend.conf
# Edit backend.conf: set bucket = "${PROJECT_ID}-tfstate"

cp example.tfvars terraform.tfvars
# Edit terraform.tfvars:
#   project_id      = "YOUR_PROJECT_ID"
#   organization_id = "YOUR_ORG_NUMERIC_ID"   # gcloud organizations list
#   region          = "us-central1"
```

Get the numeric org ID:
```bash
gcloud organizations list
```

### Step 4 — Phase 1 apply (infrastructure + MCP server)

This creates all networking, SWP, Cloud NAT, the Agent Gateway, and the
bug-tickets-mcp Cloud Run service. The Reasoning Engine is NOT created yet
(`deploy_reasoning_engine` defaults to `false`).

```bash
terraform init -backend-config=backend.conf
terraform plan
terraform apply
```

After apply, note these outputs:
```bash
terraform output nat_static_ip          # The IP the MCP server will see
terraform output bug_tickets_mcp_url    # URL used in deploy_agent.py
terraform output agent_gateway_id       # Used in --agent-gateway flag
```

> **Note:** The configuration to force all traffic to the VPC (`VPC_EGRESS_MODE_ALL_TRAFFIC`) requires an `AgentConnectivityTemplate` resource, which is not yet supported in the Google Terraform provider. The Terraform configuration in `modules/agent-gateway/main.tf` automatically handles creating, binding, unbinding, and deleting this template using `local-exec` provisioners under the hood.

### Step 5 — Build and stage agent artifacts

From the agent source directory, build the artifact bundle and write the
manifest that Terraform will reference in Phase 2.

```bash
cd ../src/software-bug-agent

# Install dependencies (uv will create a venv automatically)
uv sync

# Stage agent artifacts to GCS and write build/agent_artifacts.json
uv run python deploy_agent.py \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --mcp-url="$(cd ../../terraform && terraform output -raw bug_tickets_mcp_url)" \
  --build-only
```

The manifest is written to `../../build/agent_artifacts.json` (relative to this
directory), which is the path `terraform/main.tf` expects by default.

### Step 6 — Phase 2 apply (Reasoning Engine)

```bash
cd ../../terraform

terraform apply -var deploy_reasoning_engine=true
```

This creates the `google_vertex_ai_reasoning_engine` with
`agent_gateway_config.agent_to_anywhere_config.agent_gateway` bound, so ALL
agent egress flows through the VPC → SWP → Cloud NAT path.

```bash
terraform output reasoning_engine_name  # full resource ID
```

---

## Verification

### 1. Confirm the static NAT IP

The reserved external IP is visible in the GCP Console:
**VPC Network > IP addresses > External IP addresses** — look for the address
named `<name_prefix>-nat-ip`.

```bash
terraform output nat_static_ip
```

### 2. Send a test query to the agent

Go to **Vertex AI > Agent Engine** in the GCP Console, select the deployed
Reasoning Engine, and click **Test**. Send a prompt like:

```
List all open P1 bugs assigned to alice@quantumroast.example.
```

The agent will call `list_tickets` via MCPToolset, which makes an HTTP request
from the Reasoning Engine container — through the Agent Gateway, the SWP, and
Cloud NAT — to the Cloud Run MCP server.

### 3. Verify the egress IP in Cloud Run logs

The bug-tickets-mcp Cloud Run service logs every request. Check for calls to `/mcp`:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="bug-tickets-mcp" AND textPayload:"/mcp"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="value(textPayload)"
```

You should see the incoming requests arriving from Cloud NAT. If requests are logged with `200 OK`, the egress path is confirmed end-to-end.

### 4. Inspect SWP logs (optional)

The customer-deployed Secure Web Proxy writes access logs to Cloud Logging under `resource.type="networkservices.googleapis.com/Gateway"`. You can inspect which sessions passed through and verify that the security policy granted access (`action: ALLOWED`):

```bash
gcloud logging read \
  'resource.type="networkservices.googleapis.com/Gateway" AND resource.labels.gateway_name="agw-egress-swp-swp"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="json"
```

---

## Known Caveats and Troubleshooting

### MCP SessionNotFoundError

If you observe `google.adk.errors.session_not_found_error.SessionNotFoundError` in the Agent Engine logs, it means the backend MCP Cloud Run service is load-balancing requests across multiple instances. The Streamable HTTP transport relies on memory state. The terraform `mcp-cloud-run` module enforces `session_affinity = true` to guarantee the `POST` and `GET` requests hit the same instance. Ensure you do not manually disable it.

*Note: If you query Cloud Run logs and see `406 Not Acceptable`, this is typically caused by a manual `curl` or browser request omitting the `Accept: text/event-stream` header. The Agent's Python client correctly sets this header.*

### MCP Toolset Cold Start Timeout & Warm Instances

Cloud Run services scale to 0 by default when idle. During a cold start, container initialization can exceed the default 5.0-second connection timeout of `StreamableHTTPConnectionParams`, causing `Failed to get tools from toolset MCPToolset` and subsequent `ValueError: Tool 'list_tickets' not found`. This demo configures `timeout = 30.0` in `StreamableHTTPConnectionParams` (`tools.py`) and sets `min_instance_count = 1` in `mcp_services` (`variables.tf`) to keep the MCP service permanently warm and prevent cold-start latency.

### Agent Gateway Governance & Routing Architecture

When a Reasoning Engine is bound to an Agent Gateway in `ALL_TRAFFIC` mode, every outbound connection (including DNS and internal Google APIs) is forced through the PSC-Interface Network Attachment into the customer VPC.

To govern this traffic reliably, the demo implements a multi-layered architecture:

1. **Agent Gateway `AuthzPolicy` (Allow-All)** — The Google-managed Agent Gateway operates an internal Envoy proxy with a default-deny policy. Because CUJ2 focuses on **egress network governance via the customer SWP** and does not deploy IAP/Model Armor authorization extensions, an allow-all `AuthzPolicy` (`action = "ALLOW"`, `when = "true"`) is attached to the Agent Gateway. This is managed via `gcloud` inside `terraform_data.agent_gateway` to avoid Google Terraform provider teardown conflicts (`Error code 13`), overriding the internal `default_denied` drop and allowing all traffic to pass freely through the PSC-Interface into the customer VPC.
2. **Agent Registry Dynamic Routing Table** — `module.agent_registry_endpoints` registers all required Google API endpoints (`us-central1-aiplatform.googleapis.com`, `telemetry.googleapis.com`, etc.) and the `bug-tickets-mcp` service in the Agent Registry, granting `roles/iap.egressor` to the agent identity principal set. This satisfies the Gateway's internal routing table requirements.
3. **Private Cloud DNS Zone for `googleapis.com.`** — Google Cloud's control plane validates that any domain specified in `dnsPeeringConfig` (`googleapis.com.`) must exist as a private managed zone in Cloud DNS in the target VPC. This zone maps `*.googleapis.com.` to `private.googleapis.com` (`199.36.153.8/30`).
4. **Policy-Based Routing (PBR 1500) Bypass** — Traffic destined for `199.36.153.8/30` takes `DEFAULT_ROUTING`, bypassing the SWP so that Google API calls exit internally via **Private Google Access** (no NAT, no proxy inspection).
5. **Customer Secure Web Proxy (SWP) + Cloud NAT** — All other outbound traffic (such as calls to `bug-tickets-mcp`) matches PBR 2000, is inspected and governed by the customer-deployed **Secure Web Proxy**, and exits via **Cloud NAT** with the reserved static external IP.
6. **IPv4 Socket Resolution in `SafeAdkApp`** — The customer VPC and PSC-I network attachment operate on IPv4 only. In `safe_adk.py`, `SafeAdkApp` intercepts `socket.getaddrinfo` to fall back `AF_INET6` queries to `AF_INET` (IPv4). This prevents `aiohttp` / `aiohappyeyeballs` from attempting unreachable IPv6 connections and throwing `[Errno 101] Network is unreachable`.

### One Reasoning Engine per Agent Gateway per region

Agent Gateway currently supports **one bound Reasoning Engine per region per
gateway**. Attempting to bind a second engine to the same gateway in the same
region will fail. Use a separate gateway (or a separate project) if you need
multiple engines.

### The Agent Gateway has its own internal proxy

The Agent Gateway (`google_network_services_agent_gateway`) runs a
Google-managed internal SWP as part of its control plane. This is separate from
the **customer-deployed SWP** this demo provisions in `modules/secure-web-proxy`.
Do not confuse the two: the customer SWP is the one enforcing your security
policy and the one visible in your VPC's policy-based routes.

### SWP auto-creates a hidden Cloud Router

When the `google_network_services_gateway` (SWP) is created, GCP automatically
provisions a Cloud Router for the SWP's own proxy-originated egress. This
hidden router is separate from the explicit Cloud Router created by the
`networking` module for Cloud NAT. Both routers coexist in the same VPC and
region without conflict. `delete_swg_autogen_router_on_destroy = true` is set in
the SWP module to clean up the hidden router on `terraform destroy`.

If you see an unexpected Cloud Router in the Console (named something like
`swg-autogen-router-...`), this is it — leave it alone.

### PSC-I subnet must be /26 or larger

The Agent Gateway subnet (`agent_gateway_subnet_cidr`, default `10.20.0.0/26`)
must be **/26 or larger**. A /28 is too small for PSC-Interface to allocate
endpoints. If you change the default, do not use a prefix length larger than 26
(e.g. /27, /28).

### AgentConnectivityTemplate teardown & pre-GA reference retention

When an `AgentGateway` is deleted, Google Cloud's internal Network Services control plane retains a tombstone reference on the associated `AgentConnectivityTemplate` until background garbage collection purges it. Attempting to delete the template immediately via `delete_connectivity_template.sh` returns:
`400 FAILED_PRECONDITION: Resource is already being used by resource(s) agentGateways/agent-gateway`.

- **Zero Cost:** An idle `AgentConnectivityTemplate` is purely metadata and carries **zero cost ($0.00)**.
- **Zero Impact on Re-apply:** It does not block subsequent `terraform apply` runs — `create_connectivity_template.sh` detects the existing template and binds the new gateway to it seamlessly.
- **Delayed Cleanup:** Once Google's background reaper purges the deleted gateway's tombstone reference, you can delete the template at any time with:
  ```bash
  gcloud alpha network-services agent-connectivity-templates delete cuj2-template \
    --location=us-central1 --project=YOUR_PROJECT_ID --quiet
  ```

### Only one ACTIVE REGIONAL_MANAGED_PROXY subnet per region per VPC

GCP allows only one `ACTIVE` `REGIONAL_MANAGED_PROXY` subnet per VPC per
region. The `networking` module intentionally does **not** create a proxy-only
subnet; the `secure-web-proxy` module owns the single proxy-only subnet
(`swp_proxy_subnet_cidr`, default `10.30.0.0/24`). If you bring an existing VPC
that already has an ACTIVE REGIONAL_MANAGED_PROXY subnet, you must either remove
it or change its role to BACKUP before applying this Terraform.

### Policy-based routes and VM tags

Policy-based routes in this demo are scoped by **`src_range`** (the Agent
Gateway subnet CIDR), not by VM tags. This is correct: PSC-Interface traffic
does not carry VM tags, so `virtual_machine.tags` cannot be used to match it.

### terraform destroy — automated drain of PSC-I network attachment

The Agent Gateway module includes an automated destroy-time drain gate (`terraform_data.network_attachment_drain`) that polls `gcloud compute network-attachments describe` every 10 seconds until all connected PSC interfaces are released before Compute Engine attempts to delete the Network Attachment.

The standard teardown is fully automated:
```bash
cd terraform
terraform destroy -var deploy_reasoning_engine=true
```

*(Optional best-practice: Deleting the Reasoning Engine from the GCP Console before full destroy speeds up the teardown by initiating the background container shutdown earlier.)*

### Network Attachment with connected endpoints cannot be deleted (manual fallback)

The error `Error 412: Network Attachment with connected endpoints cannot be deleted` occurs if Compute Engine attempts to delete the Network Attachment while Google's internal service project is still asynchronously disconnecting its PSC connection (which takes ~1 to 3 minutes after the Agent Gateway is deleted).

The automated drain gate in `terraform_data.network_attachment_drain` handles this wait automatically. However, if a previous `terraform destroy` was interrupted midway via `CTRL+C`:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=us-central1

# 1. Delete the Agent Gateway if it still exists
gcloud alpha network-services agent-gateways delete agent-gateway \
  --location="${REGION}" --project="${PROJECT_ID}" --quiet || true

# 2. Delete the Connectivity Template if it still exists
./scripts/delete_connectivity_template.sh "${PROJECT_ID}" "${REGION}" "cuj2-template" || true

# 3. Wait for the tenant PSC endpoint to detach, then delete the Network Attachment
echo "Waiting for PSC endpoints to release from agent-gateway-na..."
while [ -n "$(gcloud compute network-attachments describe agent-gateway-na --region="${REGION}" --project="${PROJECT_ID}" --format='value(connectionEndpoints)' 2>/dev/null)" ]; do
  echo "Endpoints still attached. Waiting 10s..."
  sleep 10
done
echo "Endpoints released! Deleting Network Attachment..."
gcloud compute network-attachments delete agent-gateway-na \
  --region="${REGION}" --project="${PROJECT_ID}" --quiet || true

# 4. Resume Terraform destroy to clean up remaining resources
cd terraform
terraform destroy -var deploy_reasoning_engine=true
```

---

## Cleanup

```bash
# 1. Destroy all Terraform-managed resources (automated teardown)
cd terraform
terraform destroy -var deploy_reasoning_engine=true

# 2. (Optional) Delete the state bucket
gcloud storage rm -r "gs://${PROJECT_ID}-tfstate"
```

---

## Extension Points

This demo is intentionally scoped to network egress governance. The following
features are out of scope but are natural next steps:

| Extension | Where to look |
|---|---|
| **Ingress governance** (IAP + Model Armor on the agent's endpoint) | `demos/agent-gateway` (CUJ1) |
| **TLS inspection in SWP** | Add `tls_inspect = true` + `certificate_urls` to `modules/secure-web-proxy/main.tf`; provision a Certificate Manager certificate authority pool |
| **URL filtering / deny rules in SWP** | Add additional `google_network_security_gateway_security_policy_rule` resources with `session_matcher` CEL expressions |
| **VPC Service Controls perimeter** | Wrap the project in a VPC-SC perimeter; the static NAT IP can be used in an egress rule to permit traffic to the MCP server's IP range |
| **Multiple agents / gateways** | Provision one `agent-gateway` module instance per agent per region; bind each Reasoning Engine to its dedicated gateway |
