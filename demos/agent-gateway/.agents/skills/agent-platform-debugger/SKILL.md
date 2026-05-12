---
name: agent-platform-debugger
description: Debug Google Cloud Gemini Enterprise Agent Platform issues — Agent Gateway 403s, Agent Registry registration failures, Agent Identity / IAM denials, IAP egressor authorization, service-extensions delegated authz, hostname-permutation mismatches, authzPolicies / authzExtensions misconfig. Use whenever the user mentions agent gateway, agent registry, agent identity, IAP authorization for agents, ReasoningEngine 403s, "Egress request is not authorized", authzPolicies, authzExtensions, MCP server registration, or troubleshooting GCP agent platform requests — even if they don't explicitly say "debug" or name the product. Also trigger on terse symptom descriptions like "agent returning 403", "MCP tool not reachable", "authz extension denying" if there's any plausible Agent Platform context.
---

# Agent Platform Debugger

Diagnose issues across the GCP Gemini Enterprise Agent Platform: Agent Gateway, Agent Registry (Agents / MCP Servers / Endpoints), Agent Identity, Policies, IAP-delegated authorization, and service extensions.

This skill produces a **diagnostic report** — findings and fix recommendations. It does not apply fixes. The user owns the change.

## When to use this skill

Trigger when symptoms involve:

- Agent → external API requests failing with 403, especially `Egress request is not authorized`
- ReasoningEngine logs showing authz errors
- Newly-registered endpoints / MCP servers / agents that "should work" but don't
- Suspected IAP / IAM / IAM-principal-set issues for agent identities
- Authz extension or authz policy debugging
- Gateway routing / monitoring confusion
- Anything where the user mentions Agent Gateway, Agent Registry, Agent Identity, or the Gemini Enterprise Agent Platform

When *not* to use:

- General GCP IAM debugging unrelated to the Agent Platform (use direct gcloud / IAM inspection)
- Networking issues that don't involve the Agent Platform stack (e.g., raw VPC SC, plain Cloud Run auth)

## Required context (gather first)

Before doing anything else, pin down the basics. If the user hasn't supplied them, ask. Don't guess.

| Item | Why it's needed |
|---|---|
| `PROJECT_ID` and `PROJECT_NUMBER` | Most API calls take one or the other; some take both |
| `LOCATION` (region) | Registry, gateway, and IAM scope are regional. `global` is also valid for some resources |
| `AGENT_ID` (ReasoningEngine ID) or runtime identifier | To filter agent logs |
| `AGENT_GATEWAY_NAME` | To filter gateway logs |
| Agent identity (service account email or principal-set ID) | To check IAM bindings |
| Symptom: exact error text + when it started | Anchors hypothesis; "started after Terraform apply X" is gold |
| The destination the agent was trying to reach | E.g. `aiplatform`, `discoveryengine`, an MCP server, another agent |

If only some are known, proceed but call out the unknowns in the report.

## Diagnostic flow

This is a **process skill** — follow the steps in order. Most 403s resolve at step 2 or 4. Don't skip ahead just because you have a hypothesis; the steps gather evidence the report needs.

```
        ┌─────────────────────────────────────┐
        │ 0. Establish the symptom & context  │
        └────────────────┬────────────────────┘
                         ▼
        ┌─────────────────────────────────────┐
        │ 1. Pull agent logs — confirm 403    │
        └────────────────┬────────────────────┘
                         ▼
        ┌─────────────────────────────────────┐
        │ 2. Pull gateway logs — find the     │
        │    EXACT hostname being called      │
        └────────────────┬────────────────────┘
                         ▼
        ┌─────────────────────────────────────┐
        │ 3. Pull IAP logs — DRY_RUN or       │
        │    enforced? Allow or deny?         │
        └────────────────┬────────────────────┘
                         ▼
        ┌─────────────────────────────────────┐
        │ 4. Is the EXACT hostname in the     │
        │    registry (any of agents /        │
        │    mcp-servers / endpoints)?        │
        └────────┬────────────────────┬───────┘
            no   │                yes │
                 ▼                    ▼
       ┌──────────────────┐   ┌─────────────────────────────┐
       │ Root cause:      │   │ 5. Does the agent identity  │
       │ unregistered     │   │    (or its principal set)   │
       │ hostname permu-  │   │    have IAP egressor on     │
       │ tation. Recommend│   │    the registered resource? │
       │ registering all  │   └────────┬────────────────────┘
       │ five forms.      │            │
       └──────────────────┘            ▼
                            ┌─────────────────────────────┐
                            │ 6. Authz extension wired to │
                            │    the gateway? Pointing at │
                            │    IAP?                     │
                            └────────┬────────────────────┘
                                     ▼
                            ┌─────────────────────────────┐
                            │ 7. Agent identity baseline  │
                            │    roles (Vertex User,      │
                            │    Registry Viewer, logs)   │
                            └────────┬────────────────────┘
                                     ▼
                            ┌─────────────────────────────┐
                            │ 8. PrincipalSet flakiness?  │
                            │    Recommend 1:1 binding    │
                            │    test                     │
                            └─────────────────────────────┘
```

The exact log queries, gcloud commands, and curl invocations live in `references/field-manual.md`. Read that file when you reach each step — it has the copy-pasteable commands and explains what each output means.

## Tools to use

The skill assumes the agent has access to:

- **`mcp__gcloud__run_gcloud_command`** — for `gcloud` invocations (registry listing, authz-extensions describe, IAM, project lookup).
- **`mcp__gcloud-observability__list_log_entries`** — for the structured log queries in steps 1, 2, 3.
- **`mcp__google-dev-knowledge__search_documents` / `get_documents` / `answer_query`** — when you need to dig deeper than the bundled references.
- **`Bash`** — for `curl` calls to the IAP / NetworkSecurity / NetworkServices / ServiceExtensions APIs (the field manual has the exact invocations). Do *not* ask the user to run these; run them yourself when reasonable. Surface the user-runnable form in the report so they can re-run after a fix.

Run independent log queries in parallel — the agent log, gateway log, and IAP log filters in steps 1-3 don't depend on each other.

## How to use the references

The `references/` folder is layered:

- **`field-manual.md`** — read this first on every invocation. It's the operational core: hostname permutations, log queries (with the exact filters and which fields to project on), gcloud commands, curl IAM-policy fetches, the layered default-deny model (registry → gateway → authz extension → IAP/IAM → PAB), and the quick-reference step list. Most diagnoses can be done with just this file.
- **`known-issues.md`** — read when the symptom matches a recurring pattern (ReasoningEngine startup failures, missing `authz_policy` targeting the gateway, IAP-enforced startup blocks, PAB overriding IAM, gateway proxy denials with no IAP entry). Indexed by symptom; faster than the full diagnostic flow when you recognize the failure mode.
- **`agent-gateway.md`** — when the gateway itself is the suspect (routing, service-extension setup, monitoring fields).
- **`policies.md`** — when the question is about IAM modeling (PrincipalSet vs Principal, role layering, authzPolicies, PAB).
- **`agent-registry.md`** — when registration mechanics are unclear (which resource type to use, hostname-permutation registration patterns, how listing/describing works).
- **`agent-identity.md`** — when the question is about *who* the agent is (token format, identity assignment, baseline roles).

Read the smallest set that answers the question. Don't preload everything.

## Output report

Always produce a structured report. Use this template exactly — predictability matters because the user may want to share or grep these reports.

```markdown
# Agent Platform Diagnostic — <one-line summary>

## Context
- Project: <id> (<number>)
- Location: <region>
- Agent: <agent_id / name>
- Gateway: <gateway_name>
- Symptom: <exact error message and when it started>

## Evidence gathered
- Agent log query: <filter, brief summary of matches>
- Gateway log query: <filter, exact failing hostname found>
- IAP log query: <filter, decision + enforcement mode>
- Registry state: <relevant entries, IAM bindings>
- (any other tool output that mattered)

## Root cause hypothesis
<single most likely cause, stated plainly. If multiple, rank them.>

## Why this fits the evidence
<brief — connect the dots. Show which evidence rules in / rules out the hypothesis.>

## Recommended fix
<concrete actions in order. Show exact gcloud / curl / Terraform changes the user can run. If the fix is in the user's repo (Terraform), point at file:line.>

## What to verify after the fix
<the queries to re-run to confirm resolution.>

## Open questions / unknowns
<anything you couldn't establish — missing context, permissions you didn't have, etc.>
```

If you ran commands and the output is long, include only the *signal* in the report, not raw blobs. Paste the exact filter string so the user can re-run.

## Principles

- **Hostname mismatch is the #1 cause.** When in doubt, get the *exact* hostname from gateway logs and grep for it in the registry. The official docs say "register the API"; in practice you have to register five hostname permutations (six with PSC). Also watch for `unregisteredResource` in IAP audit-log labels — that's the unambiguous "hostname not in registry" signal.
- **Default-deny is the model with multiple layers.** Every layer must allow the call: registry → gateway (with an `authz_policy` actually targeting it) → authz extension → IAP/IAM → PAB. A missing entry or restriction at *any* layer produces the same 403 — your job is to find which layer. Note: the gateway's underlying egress proxy (a Google-managed Secure Web Proxy instance) can also deny calls before IAP runs; those denials show up only in load-balancer logs, not IAP audit logs.
- **PAB beats IAM Allow.** A correct `roles/iap.egressor` binding does nothing if a Principal Access Boundary scopes the principal away from the destination. Always rule out PAB before iterating on IAM bindings.
- **DRY_RUN changes everything.** If IAP is in dry-run, denials are logged but not enforced — so the real denial is somewhere else (often the gateway's underlying egress proxy, or the destination service itself). Don't waste time on IAM bindings if the IAP layer isn't actually enforcing.
- **The role is `roles/iap.egressor`.** Not `iap.tunnelResourceAccessor`, not `iap.httpsResourceAccessor`, not `iap.tunnelDestGroupUser`. Those are different IAP roles for different surfaces. The IAP authz check looks for `iap.webServiceVersions.egressViaIAP`, which only `roles/iap.egressor` grants on the Agent Gateway path.
- **Read evidence, don't assume.** Pull logs first. Don't recommend "grant role X" without showing that role X is the missing one.
- **Cite exact resource names in the report.** Service account emails, role IDs (`roles/iap.tunnelResourceAccessor`), and resource paths should appear verbatim — they're what the user needs to act on.
- **Stay in diagnosis mode.** Don't apply Terraform changes or run destructive gcloud commands. Read-only inspection only. The report is the deliverable.
