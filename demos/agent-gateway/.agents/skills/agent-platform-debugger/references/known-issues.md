# Best Known Issues (BKIs) and limitations

Concrete failure modes that come up repeatedly with the Agent Platform — symptoms and fixes. Read this when the symptom in front of you matches one of these patterns; it's faster than walking the full diagnostic flow.

---

## 1. ReasoningEngine startup: "Failed to convert project number to project ID"

**Symptom:**
- Log name: `aiplatform.googleapis.com/reasoning_engine_stderr`
- Error text: `google.api_core.exceptions.Unknown: None` or `Failed to convert project number to project ID.`
- Happens during ReasoningEngine startup, before any user code runs.

**Cause:** The ReasoningEngine's system identity (the principal set it runs under) lacks `resourcemanager.projects.get`, which the Vertex AI SDK needs to resolve the project name during init.

**Fix:** Grant `roles/browser` to the ReasoningEngine principal set:

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="principalSet://agents.global.org-${ORG_ID}.system.id.goog/attribute.platformContainer/aiplatform/projects/${PROJECT_NUMBER}" \
  --role="roles/browser"
```

---

## 2. ReasoningEngine startup: "Assembly Service failed to initialize"

**Symptom:** `[1099] ERROR: Assembly Service failed to initialize.` in `reasoning_engine_stderr`.

**Cause:** Generic "init failed" — usually a downstream symptom of either #1 (project-number resolution) or a runtime error in the agent's `set_up()` method.

**Investigation:** Pull all `severity=ERROR` from `reasoning_engine_stderr` around the same timestamp; the actual root cause is in the same window.

---

## 3. Private-preview limit: one Reasoning Engine per project bonded to an Agent Gateway

**Symptom:** Updating a Reasoning Engine to use an Agent Gateway fails with `Internal error encountered` or `The specified parameters are invalid.`

**Cause:** During the private preview, a project can have only one active ReasoningEngine ↔ AgentGateway bonding. A second bonding attempt fails.

**Fix:** Either delete the existing bonded RE / AGW, or reuse the existing AGW for any new REs.

---

## 4. 403 / "Egress request is not authorized" — missing `authz_policy` targeting the gateway

**Symptom:** Audit logs show `GatekeeperAuthorizer.AuthorizeUser` returning `Permission Denied` for `iap.webServiceVersions.egressViaIAP`.

**Cause:** The IAP authz extension exists but no `authz_policy` actually attaches it to the specific Agent Gateway. The extension is configured but the policy that targets the gateway resource is missing.

**Fix:** Verify there's an `authz_policy` in the consumer project that targets the specific `agentGateway` resource. Check with:

```bash
curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://networksecurity.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${LOCATION}/authzPolicies"
```

Look for a policy whose `target.resources[]` includes the gateway's full resource name.

---

## 5. IAP `ENFORCE` mode blocks Agent Engine startup

**Symptom:** Agent Engine instances fail to deploy or start, with 403s in startup logs.

**Cause:** With IAP in `ENFORCE` mode on the Agent Gateway, all egress is denied by default — including the bootstrap calls the agent runtime makes to `cloudresourcemanager`, `aiplatform`, `logging`, `monitoring`, etc. If those endpoints aren't registered AND the agent identity isn't granted `roles/iap.egressor` on them, startup never completes.

**Fix:** Make sure the bootstrap service set is registered in the Agent Registry (see field-manual's "Services that almost always need to be registered" list) and the agent identity has `roles/iap.egressor` on them. While debugging, flipping IAP to `DRY_RUN` lets you observe the failing destinations without blocking startup.

---

## 6. Self-signed / Private CA destinations not supported (early versions)

**Symptom:** Agent fails to connect to internal MCP servers or tools that present self-signed or Private CA-issued certificates.

**Cause:** In private-preview / early Agent Gateway, the gateway's egress proxy can't validate self-signed cert chains.

**Mitigation:** Use publicly-trusted CA certificates for internal MCP servers, or wait for the platform enhancement that adds Private CA trust-anchor support.


---

## 7. Principal Access Boundary (PAB) policies overriding IAM Allow

**Symptom:** Agent identity has the right roles bound (`roles/iap.egressor`, `roles/aiplatform.user`, etc.) and the resource is registered correctly, but calls still 403.

**Cause:** A Principal Access Boundary policy is restricting the scope of resources the principal can access. **PAB policies take precedence over IAM Allow policies** — even a correct binding does nothing if a PAB blocks the target resource.

**Investigation:** List PAB policies and their bindings for the agent identity:

```bash
# List org-wide PAB policies
gcloud iam principal-access-boundary-policies list \
  --organization="${ORGANIZATION_ID}" --location=global

# Find what's bound to a specific principal set / agent identity
gcloud iam policy-bindings search-target-policy-bindings \
  --project="${PROJECT_ID}" --target="${PRINCIPAL_SET}"

# Inspect a specific PAB
gcloud iam principal-access-boundary-policies search-policy-bindings "${PAB_POLICY_ID}" \
  --organization="${ORGANIZATION_ID}" --location=global
```

**Fix:** Either widen the PAB to include the destination resource, or remove the PAB binding from the agent's principal set if it shouldn't apply.

---

## 8. Gateway proxy denies the request before IAP runs

**Symptom:** Requests fail with no IAP audit log entry — IAP never saw them.

**Cause:** The gateway's underlying egress proxy (a Google-managed Secure Web Proxy instance) enforces a deny-by-default posture *before* IAP authz runs. When the proxy itself denies a call, IAP doesn't get a chance to evaluate, so no IAP audit-log entry is produced for that call.

**Investigation:** Pull the gateway proxy load-balancer logs (the `SECURE_WEB_GATEWAY` label refers to the underlying proxy implementation, not something the customer configures):

```
jsonPayload.@type="type.googleapis.com/google.cloud.loadbalancing.type.LoadBalancerLogEntry"
-httpRequest.requestMethod="CONNECT"
resource.labels.gateway_type="SECURE_WEB_GATEWAY"
```

Key fields: `httpRequest.status` (look for 403), `jsonPayload.authzPolicyInfo.policies.result` (overall AuthZ result), `httpRequest.requestUrl` (exact destination).

**Fix:** This is almost always upstream — usually a missing or misconfigured Agent Registry entry, an `authz_policy` that doesn't target the gateway, or a recent platform-side change. Walk the registry-verification and authz-wiring steps in `field-manual.md`. The proxy's policy itself is Google-managed and derived from your registry/policy state; you don't edit it directly.
