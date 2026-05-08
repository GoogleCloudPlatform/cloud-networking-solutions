# Design: `scripts/clear_registry_bindings.sh`

Date: 2026-05-08
Status: Approved (pending implementation plan)

## Purpose

A peer to `demos/agent-gateway/scripts/grant_agent_mcp_egress.sh` that wipes
every IAM policy binding on every Agent Registry MCP server, every endpoint,
and every Vertex AI reasoning engine ("agent") in a project/region. The grant
script *adds* a `roles/iap.egressor` binding to a single agent identity; this
script *removes everything* from each resource.

Useful as a hard reset between demos, before tearing a project down, or after
an experiment has scattered conditional bindings across the registry.

## Scope

A single bash script at `demos/agent-gateway/scripts/clear_registry_bindings.sh`,
following the conventions of the existing `grant_agent_mcp_egress.sh`:

- Apache 2.0 header (matches `docs/LICENSE_HEADER.txt`).
- `set -euo pipefail`.
- Tab indentation, same `value_for` flag-parsing helper, same `http_request`
  curl wrapper, same per-collection iteration shape.

Out of scope:

- Selective removal by role/member/condition. The script always wipes the
  whole policy. Selective grants/revokes belong in the existing grant script
  or in `gcloud projects {add,remove}-iam-policy-binding`.
- A Python or Terraform port. The shell parity with the grant script is the
  point.
- Listing or clearing IAM at the project, folder, or organization scope. Only
  per-resource policies are touched.

## Flag surface

```
--mcp           Clear bindings on all mcpServers in the registry.
--endpoints     Clear bindings on all endpoints in the registry.
--agents        Clear bindings on all reasoningEngines in the project/region.
                (No flags = all three.)
--dry-run       List target resources and their current bindings; do not write.
-h, --help      Usage.
```

Required env vars: `PROJECT_ID`, `REGION`. (`PROJECT_NUMBER` and `ORG_ID` are
not needed — no principal is being constructed.)

## Discovery

| Type        | List call                                                                                                                                              | ID extraction                              |
|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------|
| mcpServers  | `GET ${AR_BASE}/projects/${P}/locations/${R}/mcpServers`                                                                                               | `.mcpServers[].name \| split("/") \| last` |
| endpoints   | `GET ${AR_BASE}/projects/${P}/locations/${R}/endpoints`                                                                                                | `.endpoints[].name \| split("/") \| last`  |
| agents      | `gcloud beta ai reasoning-engines list --project=${PROJECT_ID} --region=${REGION} --format='value(name.basename(),displayName)' --separator=$'\t'`     | first column of each output line           |

`AR_BASE` is `https://agentregistry.googleapis.com/v1alpha`, identical to the
grant script. Reasoning engines come from a different API root, so we use
`gcloud` rather than a third hand-rolled `curl` call — it already handles auth
and pagination.

For mcpServers and endpoints we also capture `displayName` and the runtime
reference URI (the existing grant script's snippet, verbatim) so the per-line
output stays informative. For reasoning engines we capture `displayName` only.

## IAM clear

For each discovered resource ID:

1. `POST {url}:getIamPolicy` with `{"options":{"requestedPolicyVersion":3}}`.
   Used to (a) print the about-to-be-wiped bindings and (b) read the `etag`
   for the SET.
2. `POST {url}:setIamPolicy` with body
   `{"policy": {"version": 3, "etag": "<from step 1>", "bindings": []}}`.
   The `etag` round-trip protects against racing another writer; if the etag
   is stale the server rejects with 409, which surfaces via `http_request`.

URL roots (only this differs per type):

```
mcpServers:  ${IAP_BASE}/projects/${P}/locations/${R}/iap_web/agentRegistry/mcpServers/${ID}
endpoints:   ${IAP_BASE}/projects/${P}/locations/${R}/iap_web/agentRegistry/endpoints/${ID}
agents:      ${IAP_BASE}/projects/${P}/locations/${R}/iap_web/aiplatform/reasoningEngines/${ID}
```

`IAP_BASE` is `https://iap.googleapis.com/v1`, identical to the grant script.

If the GET returns a policy with no `bindings` key (i.e. nothing was ever set
on this resource), the script prints `==>  <label>  (already empty, skipping)`
and does not call SET. This avoids creating an etag where one didn't exist,
and keeps dry-run vs apply output symmetric.

## Reuse from grant_agent_mcp_egress.sh

Lifted verbatim:

- The `value_for` flag-parser helper.
- The `http_request` curl wrapper (status check + stderr body on failure).
- The `mapfile`-based discovery snippet for mcpServers/endpoints (the `jq`
  selector that emits `id\tdisplay\tservice` per line).

Not reused:

- `apply_policy`'s jq merge logic. Clearing has no merge — the SET body is
  literally `{"policy": {"version": 3, "etag": "...", "bindings": []}}`.
- The principal-construction block (`AGENT_PRINCIPAL`, `BIND_ALL_AGENTS`,
  `ROLE`, condition flags). None of these apply to a wipe.
- The substring filter helper (`matches_filter`). Per the design discussion,
  the clear script does not take per-type filters.

## Output

Per resource (apply mode):

```
==>   <displayName> (<service>)  [<id>]
cleared: <N> binding(s)
```

Per resource (dry-run):

```
==>   <displayName> (<service>)  [<id>]
would clear: <bindings JSON>
```

Per type, after the loop:

```
<collection>: cleared on <K> resource(s).
```

For reasoning engines, `<service>` is omitted (no runtime reference URI on
that resource shape) — the line shows `<displayName>  [<id>]`.

## Failure mode

Identical to the grant script:

- `set -euo pipefail` plus `http_request`'s explicit status check means any
  non-2xx from list/get/set causes immediate exit with the response body
  printed to stderr.
- No partial-success retry. The operator re-runs after fixing whatever
  caused the failure (typically auth, or a stale etag from concurrent
  modification).
- Required-env-var checks (`PROJECT_ID`, `REGION`) and required-command
  checks (`curl`, `jq`, `gcloud`) at the top, same idiom as the grant
  script.

## Testing

Manual, against a throwaway project that already has bindings in place:

1. Run `grant_agent_mcp_egress.sh --mcp --endpoints` to seed bindings.
2. Run `clear_registry_bindings.sh --dry-run` and verify the printed
   bindings match what the grant script wrote.
3. Run `clear_registry_bindings.sh` and verify the per-resource counts.
4. Re-run `clear_registry_bindings.sh --dry-run` and verify every resource
   reports as `(already empty, skipping)`.
5. Spot-check via
   `gcloud iap web get-iam-policy --resource-type=iap_web ...` (or, more
   reliably, a direct `curl :getIamPolicy`) on one mcpServer, one endpoint,
   and one reasoning engine.

No automated test harness — same posture as `grant_agent_mcp_egress.sh`,
which also has none.

## Open questions

None blocking implementation.
