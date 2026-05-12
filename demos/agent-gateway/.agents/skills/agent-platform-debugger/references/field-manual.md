# Field manual: Agent Gateway / Registry / Identity / IAP

Practical debugging knowledge for the GCP Gemini Enterprise Agent Platform, distilled from real incident triage. Read this *before* diving into the official docs — it covers the gotchas that the docs don't surface.

## The mental model

The Agent Platform runs as **default-deny egress**. An agent (typically a Vertex AI ReasoningEngine) cannot talk to *anything* outside itself unless every layer permits it:

1. **Agent Registry** — the destination must be registered as an Endpoint, MCP Server, or Agent.
2. **Agent Gateway** — intercepts the request (it sits in front of the agent's egress). Note: an `authz_policy` must explicitly target the gateway resource, otherwise the authz extension won't actually run.
3. **Service-extension (delegated authz)** — the gateway calls IAP to make an allow/deny decision.
4. **IAP / IAM** — the agent's identity must have the **IAP egressor role** (`roles/iap.egressor`, display name "IAP-secured Egressor") on the registered resource, or be in a principal set that does.
5. **Principal Access Boundary (PAB)** — even with the IAM binding correct, a PAB policy on the principal set can restrict which resources it can reach. **PAB takes precedence over IAM Allow** — a correct egressor binding does nothing if a PAB scopes the principal away from the target.

**Implementation note.** Agent Gateway is built on a Google-managed Secure Web Proxy instance that provides the egress-proxy capabilities. Customers don't configure the proxy directly — its rules are derived from registry entries and authz policies. Denials *can* originate at this proxy layer before IAP runs (no IAP audit entry exists for those calls); those show up in load-balancer logs (see Step 3b).

### Don't confuse `roles/iap.egressor` with other IAP roles

The display name "IAP-secured Egressor" maps to **`roles/iap.egressor`** — that's the role for Agent Gateway egress. Two other IAP roles exist that are easy to mistake for it but are unrelated:

| Role ID | Purpose | Use for Agent Gateway? |
|---|---|---|
| `roles/iap.egressor` | Agent egress through Agent Gateway | **Yes — this one** |
| `roles/iap.tunnelResourceAccessor` | TCP/SSH tunneling through IAP to a VM | No |
| `roles/iap.httpsResourceAccessor` | Access to IAP-protected web apps (ingress) | No |
| `roles/iap.tunnelDestGroupUser` | Member of an IAP tunnel destination group | No |

Don't substitute. The IAP authz check explicitly looks for `iap.webServiceVersions.egressViaIAP`, which only `roles/iap.egressor` grants for the Agent Gateway path.

If any layer says no, the agent gets back a 403:

```
{'code': 403, 'message': "403 Forbidden. {'message': 'Egress request is not authorized.', 'status': 'Forbidden'}"}
```

## The single biggest gotcha: hostname permutations

A Google API like `aiplatform.googleapis.com` is reachable through *many* hostnames. The agent might call any of them depending on the SDK version, regional client config, or whether mTLS is in play:

| Form | Example |
|---|---|
| Base | `aiplatform.googleapis.com` |
| Base + mTLS | `aiplatform.mtls.googleapis.com` |
| Locational | `us-central1-aiplatform.googleapis.com` |
| Locational + mTLS | `us-central1-aiplatform.mtls.googleapis.com` |
| Regional REP (public) | `aiplatform.us-central1.rep.googleapis.com` |
| Regional REP (private/PSC) | `aiplatform.us-central1.p.rep.googleapis.com` |

**The gateway matches hostnames exactly.** If you registered only `aiplatform.googleapis.com` but the SDK actually called `us-central1-aiplatform.googleapis.com`, the request gets denied — even though "the API is registered." When investigating a 403, *always* establish what hostname the agent actually called, then verify that *exact* hostname is in the registry.

A registration script typically looks like this (note all five permutations):

```bash
reg_svc "${id}"                   "${name}"                "https://${id}.googleapis.com"
reg_svc "${id}-mtls"              "${name} mTLS"           "https://${id}.mtls.googleapis.com"
reg_svc "${LOCATION}-${id}"       "${name} Locational"     "https://${LOCATION}-${id}.googleapis.com"
reg_svc "${LOCATION}-${id}-mtls"  "${name} Locational mTLS" "https://${LOCATION}-${id}.mtls.googleapis.com"
reg_svc "${id}-${LOCATION}-rep"   "${name} Regional (REP)" "https://${id}.${LOCATION}.rep.googleapis.com"
```

## Services that almost always need to be registered

For a typical agent doing inference + observability, these service IDs need endpoints registered (each with all hostname permutations above):

- `aiplatform`
- `cloudresourcemanager`
- `discoveryengine`
- `logging`
- `monitoring`
- `oauth2`
- `telemetry`
- `trace`
- `agentregistry`
- `iap`
- `modelarmor`
- `iamcredentials`

Missing any of these is the most common "agent works in dev, fails in prod" cause.

## Diagnostic playbook

### Step 1 — Confirm the symptom in agent logs

Check the ReasoningEngine logs for the 403:

```
resource.type="aiplatform.googleapis.com/ReasoningEngine"
resource.labels.location=$LOCATION
resource.labels.reasoning_engine_id=$AGENT_ID
textPayload:"403"
```

The error payload tells you *that* it failed. To learn *why*, you have to correlate to the gateway and IAP.

### Step 2 — Find the failing hostname in gateway logs

```
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.location="REGION"
resource.labels.gateway_name="AGENT_GATEWAY_NAME"
```

The gateway log entry shows the actual hostname the request was for. Write it down — you'll need it in step 4.

### Step 3 — Check IAP allow/deny decision

Narrow the noise by scoping to the egress permission and excluding base-protocol MCP method noise:

```
protoPayload.serviceName="iap.googleapis.com"
protoPayload.authorizationInfo.permission="iap.webServiceVersions.egressViaIAP"
-protoPayload.metadata.mcp_attributes.base_protocol_method="true"
```

What to read out of each entry:

- **`protoPayload.authorizationInfo[].granted`** — `true` or `false`. The bottom-line allow/deny.
- **`protoPayload.authenticationInfo.principalSubject`** — the SPIFFE / `principal://...` URI of the caller. This is the identity IAP saw; compare it to the binding's principal verbatim.
- **`protoPayload.authorizationInfo[].resource`** — the registered resource the call resolved to.
- **`labels."iap.googleapis.com/audited_resource_name"`** — if this is `unregisteredResource`, the destination hostname isn't in the registry at all (or doesn't match exactly). That's a hostname-permutation miss, full stop — go to Step 4.
- **The enforcement mode** — is IAP in dry-run? If you see metadata like this, IAP is observing but not enforcing:

  ```yaml
  service: iap.googleapis.com
  failOpen: true
  timeout: 1s
  metadata:
    iamEnforcementMode: "DRY_RUN"
  ```

  In `DRY_RUN` mode, denials are logged but the request proceeds. So if your agent is failing with a real 403 *and* IAP is in dry-run, the denial is coming from somewhere else — most often the gateway's underlying egress proxy (see Step 3b) or the destination service itself.

### Step 3b — If there's no IAP audit entry for the failing call, pull the gateway proxy load-balancer log

The gateway's underlying egress proxy can deny a request before IAP runs — when that happens, no IAP audit-log entry exists for the call. The denial is in the proxy's load-balancer log instead. The `SECURE_WEB_GATEWAY` label here refers to the proxy implementation under the hood (Google-managed; not customer-configured):

```
jsonPayload.@type="type.googleapis.com/google.cloud.loadbalancing.type.LoadBalancerLogEntry"
-httpRequest.requestMethod="CONNECT"
resource.labels.gateway_type="SECURE_WEB_GATEWAY"
```

Key fields: `httpRequest.status` (look for 403), `jsonPayload.authzPolicyInfo.policies.result` (overall AuthZ result), `httpRequest.requestUrl` (exact destination).

### Step 4 — Verify the hostname is registered (in the form the agent used)

List registry entries — pick the right resource type for the destination:

```bash
gcloud alpha agent-registry endpoints list      --project=$PROJECT_ID --location=$LOCATION
gcloud alpha agent-registry mcp-servers list    --project=$PROJECT_ID --location=$LOCATION
gcloud alpha agent-registry agents list         --project=$PROJECT_ID --location=$LOCATION
```

Grep the output for the exact hostname from step 2. If it's missing, that's the root cause — the agent is calling a permutation that was never registered.

### Step 5 — Verify IAM bindings on the registered resource

The agent's identity (or a principal set it belongs to) needs the IAP egressor role on the destination. Bindings can live at the **registry level** (covers everything) or on a **specific resource** (fine-grained).

#### Registry-level IAM policy

```bash
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -d '{}' \
  -X POST "https://iap.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/iap_web/agentRegistry:getIamPolicy" \
  -H "Content-Type: application/json"
```

#### Per-endpoint IAM policy

```bash
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -d '{}' \
  -X POST "https://iap.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/${LOCATION}/iap_web/agentRegistry/endpoints/${ENDPOINT_ID}:getIamPolicy" \
  -H "Content-Type: application/json"
```

#### Same call, but for global registry (some resources live here, not regionally):

```bash
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -d '{"options": {"requestedPolicyVersion": 3}}' \
  -X POST "https://iap.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/global/iap_web/agentRegistry:getIamPolicy" \
  -H "Content-Type: application/json"
```

When reading the returned policy, look for a binding that matches *one of*:

- The agent's service account (e.g., `serviceAccount:my-agent@…iam.gserviceaccount.com`)
- A principal set the agent belongs to

…with role `roles/iap.tunnelResourceAccessor` (the "IAP egressor" role).

### Step 6 — Inspect the gateway / authz extension wiring

#### List authz extensions (the service-extension callouts)

```bash
gcloud beta service-extensions authz-extensions list \
  --location=$LOCATION --project=$PROJECT_ID

gcloud beta service-extensions authz-extensions describe RESOURCE_NAME \
  --location=$LOCATION --project=$PROJECT_ID
```

Confirm the extension exists, is attached to the right gateway, and points at IAP.

#### List authz policies, agent gateways, and authz extensions via raw API

```bash
# authzPolicies
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://networksecurity.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${LOCATION}/authzPolicies"

# agentGateways
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://networkservices.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways"

# authzExtensions
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://serviceextensions.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${LOCATION}/authzExtensions"
```

### Step 7 — Verify the agent identity has the baseline roles

The agent identity itself needs enough permissions to function on the source side. Without these, you can get errors that look like authz failures but are actually about the agent not being able to read its own runtime config:

- `roles/aiplatform.user` (Vertex AI User) — to run the ReasoningEngine
- Agent Registry viewer role — to know what's registered
- `roles/logging.logWriter`, `roles/monitoring.metricWriter`, telemetry roles — observability
- `roles/browser` — needed for `resourcemanager.projects.get` during SDK init. Without it, the ReasoningEngine fails startup with `Failed to convert project number to project ID` (see known-issues §1).

### Step 7b — Check Principal Access Boundary (PAB) policies

Even with all the IAM bindings correct, a PAB policy can override IAM Allow and restrict the resources the principal set can reach. Symptom: the binding looks right, the resource is registered, the role is correct, and it still 403s.

```bash
# List org-wide PAB policies
gcloud iam principal-access-boundary-policies list \
  --organization="${ORGANIZATION_ID}" --location=global

# Find what's bound to the agent's principal set
gcloud iam policy-bindings search-target-policy-bindings \
  --project="${PROJECT_ID}" --target="${PRINCIPAL_SET}"
```

If a PAB binding exists for the principal set, inspect its `details.rules[].resources[]` — the destination must be in scope, otherwise the PAB silently denies.

### Step 8 — PrincipalSet vs Principal

If permissions seem flaky (works sometimes, fails sometimes; or works for one agent but not an identical sibling), suspect the **PrincipalSet** binding. Move to a **1:1 Principal binding** (bind the specific service account directly) to verify. PrincipalSet propagation can be eventually-consistent in ways that surprise you.

## Quick reference: the checks in order

When triaging a 403, walk these in order — most issues fall out at step 1 or 4:

1. Confirm the 403 in the agent log.
2. Find the *exact hostname* in the gateway log.
3. Check IAP audit log: decision, principal, `iamEnforcementMode`, and watch for `unregisteredResource` in the audited resource label.
3b. If there's no IAP audit entry for the failing call, pull the gateway proxy load-balancer log — the gateway's egress proxy can deny before IAP runs.
4. Confirm that hostname is registered (registry list + grep).
5. Check IAM on the registry / specific resource — does the agent's identity (or a principal set it's in) have `roles/iap.egressor`?
6. Check authz extensions are attached to the gateway, *and* an `authz_policy` actually targets the gateway resource (extension can exist without being applied).
7. Confirm agent identity has baseline roles (Vertex User, registry viewer, observability, browser).
7b. Check whether a PAB policy on the principal set is restricting the destination scope (PAB overrides IAM Allow).
8. If on PrincipalSet bindings and behavior is flaky, switch to direct Principal bindings.

When the symptom matches a known pattern (e.g., startup failure, missing authz_policy targeting the gateway, gateway proxy denial without IAP entry), jump straight to `known-issues.md` — it indexes the recurring failure modes by symptom.
