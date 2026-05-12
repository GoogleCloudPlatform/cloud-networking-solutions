# Agent Gateway — Debugging Reference

Curated from Google Cloud's Gemini Enterprise Agent Platform docs (Private Preview, sourced May 2026). Focused on what a debugger needs to triage failed requests through Agent Gateway.

---

## TL;DR for debugging

- Agent Gateway is a **regional** networking resource (`networkservices.googleapis.com/Gateway`) that intercepts MCP traffic in one of two modes: `CLIENT_TO_AGENT` (ingress) or `AGENT_TO_ANYWHERE` (egress). One gateway can only be one mode.
- Logs live under monitored resource type **`networkservices.googleapis.com/Gateway`** with labels `location` and `gateway_name`. The interesting payload is `jsonPayload.agentGatewayInfo`, which contains `mcpInfo` (e.g. `tools/call`, `tools/list`) and `agentRegistryResource` (the matched MCP server / agent / endpoint URN).
- Authorization is delegated through **service extensions** attached via `networksecurity.authzPolicies`. Two profile types: `REQUEST_AUTHZ` (headers only) and `CONTENT_AUTHZ` (request/response bodies, requires `ext_proc` `FULL_DUPLEX_STREAMED`).
- IAP authorization extension uses the metadata flag **`iamEnforcementMode`** with values `DRY_RUN` (audit only, requests still flow) or omitted (enforced). Logs are produced in both modes — if a request "should be denied but isn't", check this flag first.
- The gateway service account for cross-project calls (Model Armor, DNS peering) is **`service-PROJECT_NUMBER@gcp-sa-dep.iam.gserviceaccount.com`**.
- **Hard limit: max 4 custom authorization policies per Agent Gateway.** Policies with the same profile have **undefined execution order** — don't rely on ordering.
- Default-deny posture for unregistered MCP servers/tools — a 4xx may simply mean the target isn't in Agent Registry for that region.
- Agents and the gateway must be in the **same project and region** for Agent Runtime; Gemini Enterprise uses the global Agent Registry path.
- Cloud Trace only sends spans for `tools/call` (other MCP methods don't produce spans). W3C `traceparent` only — `X-Cloud-Trace-Context` is **not** supported.
- VPC Service Controls is **not** compatible. Authorization conditions only apply to MCP — non-MCP agentic protocols won't get policy enforcement.

---

## 1. What Agent Gateway is

Agent Gateway is the networking entry/exit point of the Gemini Enterprise Agent Platform. It secures and governs:

- **Client-to-Agent (ingress):** External clients reaching agents/tools on Google Cloud.
- **Agent-to-Anywhere (egress):** Agents on Google Cloud reaching external services, APIs, MCP servers, or other agents.

### Where it sits

- **Regional** resource within a single project.
- A single gateway is bound to one `governedAccessPath` — either `CLIENT_TO_AGENT` or `AGENT_TO_ANYWHERE`. They are mutually exclusive.
- "A single Agent Gateway cannot simultaneously support both Gemini Enterprise and Agent Runtime integrations" — deploy separate gateways per integration.

### Runtime support matrix

| Runtime | Ingress | Egress | Region rule |
|---|---|---|---|
| Agent Runtime | yes | yes | Agents must be in same project + region as gateway |
| Gemini Enterprise | no | yes | Gateway placement must align with multi-region setup |

### What it integrates with

- **Agent Registry** — gateway looks up metadata to enforce policies. Agents must be registered in the matching region (or `global` for Gemini Enterprise).
- **Agent Identity** — SPIFFE IDs, mTLS, DPoP (Demonstration of Proof-of-Possession).
- **IAP** (Identity-Aware Proxy) — primary IAM enforcement layer; enabled by default for egress.
- **Service Extensions** — delegation to external authz engines or Model Armor.
- **Load Balancer Authorization Policies** — fine-grained MCP-attribute access control.
- **Model Armor** — runtime prompt-injection / data-leak defense.
- **Cloud Logging / Cloud Trace** — observability.

### Key resource types

| Type | Purpose |
|---|---|
| `networkservices.agentGateways` | The gateway itself |
| `networksecurity.authzPolicies` | Attaches authorization policies to a gateway |
| `networkservices.authzExtensions` | Custom or Google-managed authorization callouts |
| `compute.networkAttachments` | PSC connectivity for egress to private networks |
| Model Armor templates | Content policies (used via authz extension) |

### Limitations to remember while debugging

- MCP-only authorization conditions; other agent protocols won't be filtered.
- Gemini Enterprise has no Client-to-Agent support.
- **VPC Service Controls is incompatible.**
- Default-deny for any MCP server / tool not registered in Agent Registry (unless explicitly allowed).

Source: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/agent-gateway-overview>

---

## 2. Setup — what to verify when something is missing

When a request fails, walk this checklist to make sure the gateway and its dependencies were assembled correctly.

### 2.1 Required APIs

- `compute.googleapis.com`
- `networksecurity.googleapis.com`
- `networkservices.googleapis.com`
- `modelarmor.googleapis.com` (optional; only if Model Armor extensions are attached)

### 2.2 Required IAM permissions on the deployer

Gateway management:
- `networkservices.agentGateways.{create,delete,get,list,update,use}`

Authorization extensions and policies:
- `networkservices.authzExtensions.{create,delete,get,list,update,use}`
- `networksecurity.authzPolicies.{create,delete,get,list}`
- `networksecurity.operations.get`

Supporting:
- `compute.networkAttachments.list`
- `compute.regions.list`
- `modelarmor.templates.list`

The permission to **attach** an authz policy to a deployed gateway is `agentGateway.use` on the target gateway.

### 2.3 Create the gateway (egress example)

`my-agent-gateway.yaml`:

```yaml
name: AGENT_GATEWAY_NAME
protocols:
  - MCP
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
  - AGENT_REGISTRY_PATH
```

`AGENT_REGISTRY_PATH` values:

- Agent Runtime (regional): `//agentregistry.googleapis.com/projects/PROJECT_ID/locations/REGION`
- Gemini Enterprise (global): `//agentregistry.googleapis.com/projects/PROJECT_ID/locations/global`

Create or update:

```bash
gcloud alpha network-services agent-gateways import AGENT_GATEWAY_NAME \
  --source="my-agent-gateway.yaml" \
  --location=LOCATION
```

### 2.4 Ingress variant

```yaml
name: AGENT_GATEWAY_NAME
protocols:
  - MCP
googleManaged:
  governedAccessPath: CLIENT_TO_AGENT
```

### 2.5 Optional VPC connectivity (egress)

PSC requirements:

- A Private Service Connect network attachment, **minimum `/28` subnet**.
- Subnet must lie within RFC1918: `10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16`.
- Avoid these reserved ranges: `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`.

YAML:

```yaml
networkConfig:
  egress:
    networkAttachment: PSC_NETWORK_ATTACHMENT_URI
  dnsPeeringConfig:
    domains:
      - DOMAIN_NAME
    targetProject: TARGET_PROJECT_ID
    targetNetwork: TARGET_NETWORK_URI
```

For DNS peering across a Shared VPC, the gateway service account needs `roles/dns.peer` on the target project:

```bash
gcloud alpha projects add-iam-policy-binding TARGET_PROJECT_ID \
  --member=serviceAccount:service-GATEWAY_PROJECT_NUMBER@gcp-sa-dep.iam.gserviceaccount.com \
  --role=roles/dns.peer
```

### 2.6 Order of operations

1. Enable APIs.
2. Create / register agents in Agent Registry (same region; or `global` for Gemini Enterprise).
3. Create the gateway resource.
4. (Optional) Configure PSC network attachment and DNS peering.
5. Create authorization extensions (`authzExtensions`).
6. Attach authorization policies (`authzPolicies`) targeting the gateway.
7. Route runtime / Gemini Enterprise traffic through the gateway.

If a stage was skipped, requests will typically fail with a default-deny or an unmatched-route response.

Source: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/set-up-agent-gateway>

---

## 3. Delegated authorization — service extensions contract

Authorization is offloaded to **authorization extensions** that the gateway calls over gRPC for each request.

### 3.1 Policy profiles

| Profile | What it sees | Use case |
|---|---|---|
| `REQUEST_AUTHZ` | HTTP request headers only | IAM checks, IAP, fast header-based rules |
| `CONTENT_AUTHZ` | Full request and response payloads | Model Armor, content scanning |

`CONTENT_AUTHZ` extensions **must** support `ext_proc` in `FULL_DUPLEX_STREAMED` mode. If the extension doesn't, requests will fail.

### 3.2 The `iamEnforcementMode` flag (IAP)

Configured on the IAP authorization extension:

```yaml
name: my-iap-request-authz-ext
service: iap.googleapis.com
failOpen: true
timeout: 1s
metadata:
  iamEnforcementMode: "DRY_RUN"   # audit-only; remove or change to enforce
```

Behaviors:

- `DRY_RUN` — IAM policy is evaluated and **logged**, but the request is **not blocked** even if it would have been denied. Use this to verify policy without breaking traffic.
- Field omitted — enforced mode (default). Failures are blocked.

**Debugging implication:** If "denied" requests are still succeeding, `iamEnforcementMode: DRY_RUN` is almost certainly set on the extension. Inspect the `authzExtension` resource directly.

### 3.3 Other extension patterns

Model Armor (CONTENT_AUTHZ):

```yaml
name: my-ma-content-authz-ext
service: modelarmor.LOCATION.rep.googleapis.com
metadata:
  model_armor_settings: '[{
    "response_template_id": "projects/MODEL_ARMOR_PROJECT_ID/...",
    "request_template_id":  "projects/MODEL_ARMOR_PROJECT_ID/..."
  }]'
failOpen: true
timeout: 1s
```

Custom FQDN extension:

```yaml
name: my-custom-authz-ext
service: mycustomauthz.internal.net
failOpen: true
timeout: 1s
wireFormat: EXT_AUTHZ_GRPC
```

`failOpen: true` means callout errors **let the request through**. If a backend is broken but traffic is still flowing, the policy is fail-open — that masks real failures.

Custom extensions targeted at FQDNs use **HTTP/2 over TLS on port 443 with no server-cert validation**. Cert misconfiguration won't cause errors but is a security smell.

### 3.4 Attaching policies

`REQUEST_AUTHZ`:

```yaml
name: my-iap-request-authz-policy
target:
  resources:
    - "projects/PROJECT_ID/locations/LOCATION/agentGateways/AGENT_GATEWAY_NAME"
policyProfile: REQUEST_AUTHZ
action: CUSTOM
customProvider:
  authzExtension:
    resources:
      - "projects/PROJECT_ID/locations/LOCATION/authzExtensions/my-iap-request-authz-ext"
```

`CONTENT_AUTHZ` is the same shape with `policyProfile: CONTENT_AUTHZ`.

### 3.5 MCP method-scoped allow rules

```yaml
name: my-authz-policy-restrict-tools
target:
  resources:
    - "projects/PROJECT_ID/locations/LOCATION/agentGateways/AGENT_GATEWAY_NAME"
policyProfile: REQUEST_AUTHZ
httpRules:
  - to:
      operations:
        - mcp:
            baseProtocolMethodsOption: MATCH_BASE_PROTOCOL_METHODS
            methods:
              - name: "tools/list"
              - name: "tools/call"
                params:
                  - exact: "get_weather"
```

**Critical:** When using `ALLOW` policies for MCP, set `baseProtocolMethodsOption: MATCH_BASE_PROTOCOL_METHODS` or you'll silently break the core MCP RPCs (`initialize`, `logging`, `completion`, `notifications`, `ping`).

### 3.6 Cross-project Model Armor IAM

Gateway service account: `service-PROJECT_NUMBER@gcp-sa-dep.iam.gserviceaccount.com`

| Where | Role |
|---|---|
| Gateway project | `roles/modelarmor.calloutUser` |
| Gateway project | `roles/serviceusage.serviceUsageConsumer` |
| Model Armor project | `roles/modelarmor.user` |

### 3.7 Hard limits and gotchas

- **Max 4 custom authorization policies per Agent Gateway.**
- Multiple policies sharing the same profile have **undefined execution order**.
- `CONTENT_AUTHZ` requires `ext_proc` `FULL_DUPLEX_STREAMED`.
- Cross-project Model Armor needs all three IAM bindings above; missing any one causes silent extension failures (and `failOpen: true` masks them).

Source: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/delegate-authorization>

---

## 4. Logging and monitoring

### 4.1 Monitored resource

```
resource.type   = "networkservices.googleapis.com/Gateway"
resource.labels.location      = REGION
resource.labels.gateway_name  = AGENT_GATEWAY_NAME
```

Logs are produced for **all** traffic, including dry-run mode requests.

### 4.2 Standard log filter

```
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.location="REGION"
resource.labels.gateway_name="AGENT_GATEWAY_NAME"
```

`gcloud` equivalent:

```bash
gcloud logging read \
  'resource.type="networkservices.googleapis.com/Gateway"
   resource.labels.location="us-central1"
   resource.labels.gateway_name="my-gateway"' \
  --limit=50 --format=json
```

### 4.3 Log entry fields

Required `LogEntry` fields:

| Field | Notes |
|---|---|
| `severity`, `insertId`, `timestamp`, `receiveTimestamp` | standard |
| `trace`, `traceSampled`, `logName` | standard |
| `httpRequest` | standard `HttpRequest` proto |
| `resource` | the `MonitoredResource` (type above) |
| `jsonPayload` | gateway-specific payload |

`jsonPayload` contents:

| Field | Description |
|---|---|
| `agentGatewayInfo` | Wrapper for gateway-specific request info |
| `agentGatewayInfo.mcpInfo` | The MCP method (e.g. `tools/list`, `tools/call`) and primary parameter (e.g. tool name for `tools/call`) |
| `agentGatewayInfo.agentRegistryResource` | Agent Registry resource name of the matched MCP server / agent / endpoint |

### 4.4 Useful log filters for debugging

Failed requests only:

```
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.gateway_name="AGENT_GATEWAY_NAME"
httpRequest.status>=400
```

Specific MCP method:

```
resource.type="networkservices.googleapis.com/Gateway"
jsonPayload.agentGatewayInfo.mcpInfo.method="tools/call"
```

Specific tool name (when method is `tools/call`):

```
resource.type="networkservices.googleapis.com/Gateway"
jsonPayload.agentGatewayInfo.mcpInfo.method="tools/call"
jsonPayload.agentGatewayInfo.mcpInfo.params:"get_weather"
```

Requests against a specific registered agent / MCP server:

```
resource.type="networkservices.googleapis.com/Gateway"
jsonPayload.agentGatewayInfo.agentRegistryResource:"my-mcp-server"
```

### 4.5 Metrics

Agent Gateway exports **Service Extensions** metrics to Cloud Monitoring. When triaging extension callout failures (timeouts, 5xx from the extension, fail-open behavior), use the same metrics described in Cloud Load Balancing callouts: <https://docs.cloud.google.com/service-extensions/docs/monitor-lb-callouts#monitoring_metrics_for_callouts>

### 4.6 Cloud Trace

Cloud Trace covers MCP tool calls but with caveats:

- Only `tools/call` operations produce spans. `tools/list`, `initialize`, etc. **don't**.
- Only **W3C `traceparent`** is supported. The legacy `X-Cloud-Trace-Context` header is ignored.
- Unauthenticated, unauthorized, or policy-rejected requests may not appear in trace samples.

Trace can be triggered by either an HTTP `traceparent` header or by setting `params._meta.traceparent` in the MCP body, with the W3C sampled flag set to `1`.

Resource attributes on MCP spans:

| Attribute | Description |
|---|---|
| `cloud.account.id` | Billing project ID |
| `cloud.provider` | always `gcp` |
| `gcp.mcp.server.id` | URN of the MCP server |
| `gcp.project_id` | Project where telemetry is sent |

Span attributes:

| Attribute | Description |
|---|---|
| `error.message` | Error message on failure |
| `error.type` | Low-cardinality error type |
| `gen_ai.operation.name` | Always `execute_tool` for MCP |
| `gen_ai.tool.name` | Invoked tool name |
| `jsonrpc.protocol.version` | JSON-RPC version |
| `jsonrpc.request.id` | Unique JSON-RPC invocation ID |
| `mcp.method.name` | e.g. `tools/call` |
| `mcp.protocol.version` | MCP version |

Scope attribute:

| Attribute | Description |
|---|---|
| `gcp.server.service` | MCP server service name (e.g. `bigquery.googleapis.com`) |

Source: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/monitor-agent-gateway>
Trace details: <https://docs.cloud.google.com/mcp/monitor-mcp-tool-use-with-cloud-trace>

---

## 5. Common failure modes and where to look

| Symptom | Likely cause | First place to look |
|---|---|---|
| All requests pass even after attaching a deny/IAP policy | Extension has `iamEnforcementMode: "DRY_RUN"` | The `authzExtension` resource metadata |
| Extension errors but traffic keeps flowing | `failOpen: true` on the extension | The `authzExtension` definition; Service Extensions metrics |
| `tools/list` works but `tools/call` for a specific tool fails | Tool not in Agent Registry, or restricted by an MCP method-scoped policy | Agent Registry; `httpRules.to.operations.mcp.methods` in `authzPolicies` |
| Core MCP methods (`initialize`, `ping`, `notifications`) break after adding an ALLOW policy | Missing `baseProtocolMethodsOption: MATCH_BASE_PROTOCOL_METHODS` | The `httpRules` block of the policy |
| Cross-project Model Armor extension fails silently | Missing one of `roles/modelarmor.calloutUser`, `roles/serviceusage.serviceUsageConsumer` (gateway project) or `roles/modelarmor.user` (Model Armor project) on `service-PROJECT_NUMBER@gcp-sa-dep.iam.gserviceaccount.com` | IAM bindings in both projects |
| DNS resolution for private targets fails (egress) | Missing `roles/dns.peer` for the gateway service account on Shared VPC host project, or PSC subnet too small / overlapping reserved ranges | `dnsPeeringConfig`; PSC network attachment |
| Requests denied with no log entry of the policy | Default-deny because the agent / MCP server isn't in Agent Registry for that region | Agent Registry registration for the matching region |
| Gateway accepts neither ingress nor expected egress | `governedAccessPath` is the wrong mode (ingress vs egress); modes are mutually exclusive | YAML `googleManaged.governedAccessPath` |
| New policy has no effect | Already 4 custom authz policies attached (the cap), or two same-profile policies in undefined order | List `authzPolicies` for the gateway |
| Can't see request bodies in logs / can't apply content rules | Using `REQUEST_AUTHZ` profile (headers only); needs `CONTENT_AUTHZ` extension that supports `ext_proc` `FULL_DUPLEX_STREAMED` | Policy profile and extension capabilities |
| Trace headers don't propagate | Sending `X-Cloud-Trace-Context`; only W3C `traceparent` is honored for MCP | Client trace header |
| No spans for `tools/list` | Expected — only `tools/call` produces spans | n/a |
| Calls fail in a perimeter project | VPC Service Controls is incompatible with Agent Gateway | Move out of perimeter or grant ingress/egress rules accordingly |

---

## 6. Quick gcloud cheatsheet

```bash
# Inspect the gateway
gcloud alpha network-services agent-gateways describe AGENT_GATEWAY_NAME \
  --location=LOCATION

# List authorization extensions
gcloud alpha network-services authz-extensions list --location=LOCATION

# List authorization policies
gcloud alpha network-security authz-policies list --location=LOCATION

# Pull recent gateway logs
gcloud logging read \
  'resource.type="networkservices.googleapis.com/Gateway"
   resource.labels.gateway_name="AGENT_GATEWAY_NAME"' \
  --limit=20 --freshness=1h --format=json

# Filter on errors only
gcloud logging read \
  'resource.type="networkservices.googleapis.com/Gateway"
   resource.labels.gateway_name="AGENT_GATEWAY_NAME"
   httpRequest.status>=400' \
  --limit=50 --freshness=1h
```

---

## Source URLs

- Overview: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/agent-gateway-overview>
- Setup: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/set-up-agent-gateway>
- Delegate authorization: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/delegate-authorization>
- Monitor: <https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/monitor-agent-gateway>
- MCP + Cloud Trace (referenced for trace fields): <https://docs.cloud.google.com/mcp/monitor-mcp-tool-use-with-cloud-trace>
