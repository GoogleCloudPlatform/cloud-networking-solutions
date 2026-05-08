# clear_registry_bindings.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `demos/agent-gateway/scripts/clear_registry_bindings.sh`, a peer to `grant_agent_mcp_egress.sh` that wipes every IAM policy binding on every Agent Registry MCP server, every endpoint, and every Vertex AI reasoning engine ("agent") in a project/region.

**Architecture:** A single bash script that mirrors `grant_agent_mcp_egress.sh` in shape: arg parser → required-env/required-command checks → discovery loop per resource type → per-resource `getIamPolicy` (read+display) → `setIamPolicy` with empty bindings (skipped under `--dry-run`). Reuses the `value_for` flag-parser, the `http_request` curl wrapper, and the `mapfile`+`jq` discovery snippet from the grant script verbatim. Reasoning engines are listed via `gcloud beta ai reasoning-engines list` because they live under a different REST root (`iap_web/aiplatform/...`) than the registry collections.

**Tech Stack:** Bash 4+, `curl`, `jq`, `gcloud` (with `beta` component for reasoning engines). No package manager, no test framework — manual verification against a throwaway GCP project, same posture as the existing grant script.

**Spec:** [`docs/superpowers/specs/2026-05-08-clear-registry-bindings-design.md`](../specs/2026-05-08-clear-registry-bindings-design.md)

---

## File Structure

| Path | Action | Purpose |
|------|--------|---------|
| `demos/agent-gateway/scripts/clear_registry_bindings.sh` | Create | The new helper. Single file, self-contained, executable bit set. |

No other files change. The plan does not modify `grant_agent_mcp_egress.sh`, the Terraform modules, or the README — keeping blast radius to one new file is the whole point.

---

## Conventions inherited from `grant_agent_mcp_egress.sh`

The new script must match these so the two read as siblings:

- Apache 2.0 header at top, copied verbatim from `docs/LICENSE_HEADER.txt` with the `#` prefix style used by the grant script (lines 2–16 of the grant script).
- `set -euo pipefail` immediately after the header doc-comment block.
- Tab indentation throughout the body (the grant script's `case` arms, `if` blocks, function bodies all use literal tab characters).
- Help text is the doc-comment block at the top of the file, printed by `sed -n '<start>,<end>p' "$0"` from the `-h | --help` case arm. Pick the line range *after* writing the doc comment in Task 2 — the existing script's `17,79p` is specific to its own line numbers.
- Required-command check uses the `for cmd in curl jq gcloud; do ...` idiom from the grant script (lines 181–186).

---

### Task 1: Create the script file with shebang, license header, and executable bit

**Files:**
- Create: `demos/agent-gateway/scripts/clear_registry_bindings.sh`

- [ ] **Step 1: Write the file with shebang and license header**

Create `demos/agent-gateway/scripts/clear_registry_bindings.sh` with exactly this content:

```bash
#!/usr/bin/env bash
#
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x demos/agent-gateway/scripts/clear_registry_bindings.sh`

- [ ] **Step 3: Verify shellcheck is happy with what's there so far**

Run: `shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0. (If `shellcheck` is missing, install with `sudo apt-get install -y shellcheck` or equivalent — the file is too small to skip linting.)

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(agent-gateway): scaffold clear_registry_bindings.sh"
jj new
```

(The user uses jj. `jj describe` sets the message on the current change, `jj new` starts a fresh empty change for the next task. No `jj commit` needed.)

---

### Task 2: Add the doc-comment usage block

**Files:**
- Modify: `demos/agent-gateway/scripts/clear_registry_bindings.sh` (append after the license header)

- [ ] **Step 1: Append the doc-comment block**

Append the following to `demos/agent-gateway/scripts/clear_registry_bindings.sh`. This becomes the script's `-h`/`--help` output, so write it as user-facing documentation:

```bash
#
# Clears every IAM policy binding on every Agent Registry MCP server, every
# Agent Registry endpoint, and every Vertex AI reasoning engine ("agent") in
# a project/region. The peer to grant_agent_mcp_egress.sh: that script *adds*
# a roles/iap.egressor binding to a single agent identity; this script
# *removes everything* from each resource.
#
# Per-resource bindings are documented at:
#   https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/assign-identity-iam#agent-to-mcp-server
#   https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/assign-identity-iam#agent-to-endpoint
#
# This script calls the IAP REST endpoints directly (gcloud SDK 552 does not
# yet ship `gcloud beta iap web add-iam-policy-binding --mcpServer=...` /
# `--endpoint=...`):
#   - List mcpServers: https://agentregistry.googleapis.com/v1alpha/projects/{P}/locations/{R}/mcpServers
#   - List endpoints:  https://agentregistry.googleapis.com/v1alpha/projects/{P}/locations/{R}/endpoints
#   - List agents:     gcloud beta ai reasoning-engines list (different REST root)
#   - Per-resource IAM:
#       https://iap.googleapis.com/v1/projects/{P}/locations/{R}/iap_web/agentRegistry/{mcpServers,endpoints}/{ID}:{get,set}IamPolicy
#       https://iap.googleapis.com/v1/projects/{P}/locations/{R}/iap_web/aiplatform/reasoningEngines/{ID}:{get,set}IamPolicy
#
# Required env vars:
#   PROJECT_ID       e.g. duncanjames-agw-tf
#   REGION           e.g. us-central1
#
# Resource-type selection flags (boolean — none set means all three):
#   --mcp                    Clear bindings on MCP servers in the registry.
#   --endpoints              Clear bindings on endpoints in the registry.
#   --agents                 Clear bindings on reasoning engines in the project/region.
#
# Behavior flags:
#   --dry-run                List target resources and their current bindings;
#                            do not call setIamPolicy. Use this before --apply
#                            to verify scope.
#   -h, --help               Print this usage and exit.
```

- [ ] **Step 2: Verify the file is still well-formed**

Run: `bash -n demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0. (No executable code yet, but the parse must succeed.)

Run: `shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0.

- [ ] **Step 3: Commit**

```bash
jj describe -m "docs(agent-gateway): add usage doc-comment to clear_registry_bindings.sh"
jj new
```

---

### Task 3: Add `set -euo pipefail`, the arg parser, and required-env/command checks

**Files:**
- Modify: `demos/agent-gateway/scripts/clear_registry_bindings.sh` (append)

- [ ] **Step 1: Append the prologue**

Append exactly this block. The `value_for` helper is identical to the one in `grant_agent_mcp_egress.sh:88-96`. Indentation in the `case`/`if` arms is **literal tab characters**, not spaces — match the grant script.

```bash

set -euo pipefail

# Resource-type selection (CLI-only; default = all three when none is set).
DO_MCP=
DO_ENDPOINTS=
DO_AGENTS=
DRY_RUN=

# value_for <flag-name> <candidate>: echo <candidate> if present and not
# itself a flag; error otherwise. Intended call:  value_for "$1" "${2:-}".
value_for() {
	local flag="$1" candidate="${2:-}"
	if [ -z "${candidate}" ] || [[ ${candidate} == --* ]]; then
		echo "${flag} requires a value" >&2
		exit 1
	fi
	printf '%s' "${candidate}"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--mcp)
		DO_MCP=1
		shift
		;;
	--endpoints)
		DO_ENDPOINTS=1
		shift
		;;
	--agents)
		DO_AGENTS=1
		shift
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	-h | --help)
		# Print the doc-comment block (lines 17 through the blank line before
		# `set -euo pipefail`). The line range is hand-tuned for this file.
		sed -n '17,55p' "$0"
		exit 0
		;;
	*)
		echo "Unknown flag: $1 (run with -h for usage)" >&2
		exit 1
		;;
	esac
done
if [ -z "${DO_MCP}" ] && [ -z "${DO_ENDPOINTS}" ] && [ -z "${DO_AGENTS}" ]; then
	DO_MCP=1
	DO_ENDPOINTS=1
	DO_AGENTS=1
fi

: "${PROJECT_ID:?PROJECT_ID is required}"
: "${REGION:?REGION is required}"

for cmd in curl jq gcloud; do
	command -v "$cmd" >/dev/null 2>&1 || {
		echo "Missing required command: $cmd" >&2
		exit 1
	}
done

TOKEN="$(gcloud auth print-access-token)"
AR_BASE="https://agentregistry.googleapis.com/v1alpha"
IAP_BASE="https://iap.googleapis.com/v1"
```

- [ ] **Step 2: Tune the help-text line range**

Open `demos/agent-gateway/scripts/clear_registry_bindings.sh` in your editor. Find the first line of the doc-comment block (the `# Clears every IAM policy binding...` line) and the last line of it (the `#   -h, --help               Print this usage and exit.` line). Update the `sed -n '17,55p' "$0"` literal in the `-h | --help` case arm to match those line numbers exactly. The `17` and `55` in the snippet above are best-guess starting values; verify against the actual file.

Run: `awk '/^# Clears every IAM policy binding/{print NR; exit}' demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: the start line number (probably 17 or 18).

Run: `awk '/^#   -h, --help/{print NR; exit}' demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: the end line number.

Edit the `sed -n` literal so the range matches.

- [ ] **Step 3: Verify the help output**

Run: `demos/agent-gateway/scripts/clear_registry_bindings.sh --help`
Expected output: the doc-comment block from Task 2, with no leading/trailing junk lines. The first printed line should be `# Clears every IAM policy binding on every Agent Registry MCP server, every`. The last should be `#   -h, --help               Print this usage and exit.`.

If the range is off by one or two lines, retune.

- [ ] **Step 4: Verify required-env enforcement**

Run: `unset PROJECT_ID REGION; demos/agent-gateway/scripts/clear_registry_bindings.sh --mcp 2>&1 | head -1`
Expected: `demos/agent-gateway/scripts/clear_registry_bindings.sh: line N: PROJECT_ID: PROJECT_ID is required`
(The `set -e` plus `${PROJECT_ID:?...}` idiom produces exactly this error.)

Run: `PROJECT_ID=foo unset REGION; demos/agent-gateway/scripts/clear_registry_bindings.sh --mcp 2>&1 | head -1`
Expected: `demos/agent-gateway/scripts/clear_registry_bindings.sh: line N: REGION: REGION is required`

- [ ] **Step 5: Verify unknown-flag rejection**

Run: `PROJECT_ID=foo REGION=bar demos/agent-gateway/scripts/clear_registry_bindings.sh --bogus 2>&1`
Expected: `Unknown flag: --bogus (run with -h for usage)`, exit code 1.

- [ ] **Step 6: shellcheck**

Run: `shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0.

- [ ] **Step 7: Commit**

```bash
jj describe -m "feat(agent-gateway): add arg parser and prologue to clear_registry_bindings.sh"
jj new
```

---

### Task 4: Add the `http_request` helper and the per-resource `clear_policy` function

**Files:**
- Modify: `demos/agent-gateway/scripts/clear_registry_bindings.sh` (append)

- [ ] **Step 1: Append the helpers**

Append exactly this block. The `http_request` helper is copied verbatim from `grant_agent_mcp_egress.sh:207-222`. The `clear_policy` function is new — it is much simpler than the grant script's `apply_policy` because there is nothing to merge: the SET body is always `{"policy": {"version": 3, "etag": "...", "bindings": []}}`.

```bash

# http_request <output_file> <curl args…>
# Wraps curl so the response body is always written to <output_file> and the
# HTTP status is checked explicitly. On 4xx/5xx, prints "FAILED (HTTP <code>):"
# and the body to stderr, then returns non-zero. On success, returns 0.
http_request() {
	local out="$1"
	shift
	local code
	code="$(curl -sS -o "${out}" -w '%{http_code}' "$@")"
	if [ "${code}" -lt 200 ] || [ "${code}" -ge 300 ]; then
		echo "FAILED (HTTP ${code}):" >&2
		cat "${out}" >&2
		echo >&2
		return 1
	fi
}

# clear_policy <iam_url_base> <label>
# GET the current policy, print its bindings (so the operator sees what is
# being wiped or what would be wiped under --dry-run), then SET an empty
# bindings array reusing the etag from the GET. If the GET returns no
# .bindings key (resource has never had a policy set), prints
# "(already empty, skipping)" and does NOT call SET.
clear_policy() {
	local iam_url="$1" label="$2"
	local resp="/tmp/iam_resp.$$"
	local count etag body

	if ! http_request "${resp}" -X POST \
		-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
		-d '{"options":{"requestedPolicyVersion":3}}' "${iam_url}:getIamPolicy"; then
		rm -f "${resp}"
		exit 1
	fi

	count="$(jq '(.bindings // []) | length' <"${resp}")"
	etag="$(jq -r '.etag // ""' <"${resp}")"

	echo "==>   ${label}"
	if [ "${count}" -eq 0 ]; then
		echo "      (already empty, skipping)"
		rm -f "${resp}"
		return 0
	fi

	if [ -n "${DRY_RUN}" ]; then
		printf '      would clear: '
		jq -c '.bindings' <"${resp}"
		rm -f "${resp}"
		return 0
	fi

	body="$(jq -n --arg etag "${etag}" '
    {policy: ({bindings: [], version: 3}
              + (if $etag == "" then {} else {etag: $etag} end))}
  ')"

	if ! http_request "${resp}" -X POST \
		-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
		-d "${body}" "${iam_url}:setIamPolicy"; then
		rm -f "${resp}"
		exit 1
	fi
	echo "      cleared: ${count} binding(s)"
	rm -f "${resp}"
}
```

- [ ] **Step 2: Parse-check**

Run: `bash -n demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0.

- [ ] **Step 3: shellcheck**

Run: `shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0. If shellcheck warns about the heredoc-style jq script (SC2016 about variables in single quotes), that is a *false positive* — `jq` uses `$etag` to refer to the variable bound via `--arg`, not a shell variable. Annotate with `# shellcheck disable=SC2016` immediately above the `body="$(jq -n ...` line if shellcheck flags it.

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(agent-gateway): add http_request and clear_policy helpers"
jj new
```

---

### Task 5: Add the registry-collection processor (mcpServers, endpoints)

**Files:**
- Modify: `demos/agent-gateway/scripts/clear_registry_bindings.sh` (append)

- [ ] **Step 1: Append the function**

Append exactly this block. The list URL, the `mapfile`+`jq` discovery snippet, and the empty-list message all match `grant_agent_mcp_egress.sh:295-329` so the two scripts produce comparable output.

```bash

# process_registry_collection <collection>
# <collection> is "mcpServers" or "endpoints" — used as both the list-URL leaf,
# the JSON top-level key, and the IAP IAM URL segment.
# Lists every resource of that type and clears the policy on each.
process_registry_collection() {
	local collection="$1"
	local list_resp="/tmp/iam_resp.$$"

	echo "--- ${collection} ---"
	if ! http_request "${list_resp}" -H "Authorization: Bearer ${TOKEN}" \
		"${AR_BASE}/projects/${PROJECT_ID}/locations/${REGION}/${collection}"; then
		rm -f "${list_resp}"
		return 1
	fi

	local entries
	mapfile -t entries < <(jq -r --arg c "${collection}" '
    .[$c] // []
    | .[]
    | [
        (.name | split("/") | last),
        (.displayName // ""),
        ((.attributes["agentregistry.googleapis.com/system/RuntimeReference"].uri // "")
          | split("/") | last)
      ]
    | @tsv
  ' <"${list_resp}")
	rm -f "${list_resp}"

	if [ "${#entries[@]}" -eq 0 ]; then
		echo "No ${collection} found in ${PROJECT_ID}/${REGION}." >&2
		return 0
	fi

	local cleared=0 line id display service
	for line in "${entries[@]}"; do
		IFS=$'\t' read -r id display service <<<"${line}"
		clear_policy \
			"${IAP_BASE}/projects/${PROJECT_ID}/locations/${REGION}/iap_web/agentRegistry/${collection}/${id}" \
			"${display} (${service})  [${id}]"
		cleared=$((cleared + 1))
	done

	if [ -n "${DRY_RUN}" ]; then
		echo "${collection}: would process ${cleared} resource(s)."
	else
		echo "${collection}: processed ${cleared} resource(s)."
	fi
	echo
}
```

- [ ] **Step 2: Parse-check + shellcheck**

Run: `bash -n demos/agent-gateway/scripts/clear_registry_bindings.sh && shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0 from both.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(agent-gateway): add registry-collection processor"
jj new
```

---

### Task 6: Add the reasoning-engine processor

**Files:**
- Modify: `demos/agent-gateway/scripts/clear_registry_bindings.sh` (append)

- [ ] **Step 1: Append the function**

Reasoning engines live under a different REST root (`iap_web/aiplatform/reasoningEngines/...`) and a different listing API (`gcloud beta ai reasoning-engines list`). The function shape mirrors `process_registry_collection` so the output is symmetric, but discovery uses `gcloud` instead of `curl`:

```bash

# process_reasoning_engines
# Lists all reasoning engines in PROJECT_ID/REGION via gcloud and clears the
# policy on each. The IAP IAM URL root is iap_web/aiplatform (NOT
# iap_web/agentRegistry — reasoning engines are not registry resources).
process_reasoning_engines() {
	echo "--- agents (reasoningEngines) ---"

	local entries
	# `--format=value(...)` emits one row per resource, columns separated by
	# tabs. `name.basename()` extracts the trailing ID from the full name
	# (e.g. projects/.../reasoningEngines/1234567890 -> 1234567890).
	mapfile -t entries < <(gcloud beta ai reasoning-engines list \
		--project="${PROJECT_ID}" --region="${REGION}" \
		--format='value(name.basename(),displayName)' --separator=$'\t' 2>/dev/null || true)

	if [ "${#entries[@]}" -eq 0 ]; then
		echo "No reasoning engines found in ${PROJECT_ID}/${REGION}." >&2
		echo
		return 0
	fi

	local cleared=0 line id display
	for line in "${entries[@]}"; do
		IFS=$'\t' read -r id display <<<"${line}"
		clear_policy \
			"${IAP_BASE}/projects/${PROJECT_ID}/locations/${REGION}/iap_web/aiplatform/reasoningEngines/${id}" \
			"${display}  [${id}]"
		cleared=$((cleared + 1))
	done

	if [ -n "${DRY_RUN}" ]; then
		echo "reasoningEngines: would process ${cleared} resource(s)."
	else
		echo "reasoningEngines: processed ${cleared} resource(s)."
	fi
	echo
}
```

- [ ] **Step 2: Parse-check + shellcheck**

Run: `bash -n demos/agent-gateway/scripts/clear_registry_bindings.sh && shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0 from both.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(agent-gateway): add reasoning-engine processor"
jj new
```

---

### Task 7: Add the run banner and the dispatch tail

**Files:**
- Modify: `demos/agent-gateway/scripts/clear_registry_bindings.sh` (append)

- [ ] **Step 1: Append the banner and dispatch**

Append exactly this block. The banner mirrors `grant_agent_mcp_egress.sh:196-205` so a side-by-side `diff` of operator output looks reasonable.

```bash

process_to=()
[ -n "${DO_MCP}" ] && process_to+=("mcpServers")
[ -n "${DO_ENDPOINTS}" ] && process_to+=("endpoints")
[ -n "${DO_AGENTS}" ] && process_to+=("reasoningEngines")

echo "Clearing IAM policy bindings on:"
echo "Project: ${PROJECT_ID}  Region: ${REGION}"
echo "Process: ${process_to[*]}"
if [ -n "${DRY_RUN}" ]; then
	echo "Mode:    DRY RUN (no setIamPolicy calls will be made)"
else
	echo "Mode:    APPLY"
fi
echo

if [ -n "${DO_MCP}" ]; then
	process_registry_collection "mcpServers"
fi
if [ -n "${DO_ENDPOINTS}" ]; then
	process_registry_collection "endpoints"
fi
if [ -n "${DO_AGENTS}" ]; then
	process_reasoning_engines
fi

echo "Done."
```

- [ ] **Step 2: Parse-check + shellcheck**

Run: `bash -n demos/agent-gateway/scripts/clear_registry_bindings.sh && shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0 from both.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(agent-gateway): wire up dispatch tail in clear_registry_bindings.sh"
jj new
```

---

### Task 8: Pre-commit on the new file

**Files:** none (verification only)

- [ ] **Step 1: Run pre-commit**

Per the user's global instructions (`~/.claude/CLAUDE.md`), run pre-commit on changed files before declaring the task done:

Run: `pre-commit run --files demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: all hooks pass (or auto-fix with no remaining diff). If any hook auto-modifies the file, re-stage in jj (the change is already in the working copy because jj tracks the working directory) and re-run pre-commit until it is clean.

- [ ] **Step 2: If pre-commit modified the file, commit the fix**

```bash
jj describe -m "style(agent-gateway): pre-commit fixes for clear_registry_bindings.sh"
jj new
```

If pre-commit had no changes, skip this step.

---

### Task 9: Manual smoke test against a throwaway project

**Files:** none (verification only — requires an authenticated `gcloud` session against a project where you can safely add and remove IAM bindings)

This task is the equivalent of the test suite. It verifies the script end-to-end against real GCP APIs because there is no automated harness for it.

- [ ] **Step 1: Set required env**

Run (substitute your own values):

```bash
export PROJECT_ID="duncanjames-agw-tf"
export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
export ORG_ID="$(gcloud organizations list --format='value(name.basename())' --limit=1)"
export REGION="us-central1"
```

- [ ] **Step 2: Seed at least one binding via the grant script**

Run:

```bash
demos/agent-gateway/scripts/grant_agent_mcp_egress.sh --bind-all-agents --mcp --endpoints
```

Expected: the script prints `==>` lines for each mcpServer and endpoint, each followed by a JSON binding list that now includes `roles/iap.egressor`. If the project has no mcpServers or endpoints, deploy them first per the demo README — there is nothing to test against an empty registry.

- [ ] **Step 3: Dry-run the new script**

Run:

```bash
demos/agent-gateway/scripts/clear_registry_bindings.sh --dry-run
```

Expected output structure:

```
Clearing IAM policy bindings on:
Project: <PROJECT_ID>  Region: <REGION>
Process: mcpServers endpoints reasoningEngines
Mode:    DRY RUN (no setIamPolicy calls will be made)

--- mcpServers ---
==>   <displayName> (<service>)  [<id>]
      would clear: [{"role":"roles/iap.egressor","members":["principalSet://..."]}]
... (one ==> per mcpServer)
mcpServers: would process N resource(s).

--- endpoints ---
... (same shape)
endpoints: would process M resource(s).

--- agents (reasoningEngines) ---
==>   <displayName>  [<id>]
      would clear: [...]   OR   (already empty, skipping)
reasoningEngines: would process K resource(s).

Done.
```

Verify: the bindings printed under `would clear:` for mcpServers/endpoints include the `roles/iap.egressor` binding seeded in Step 2.

- [ ] **Step 4: Apply for real**

Run:

```bash
demos/agent-gateway/scripts/clear_registry_bindings.sh
```

Expected: the same `==>` lines, but each non-empty resource now prints `cleared: N binding(s)` instead of `would clear: ...`. Each previously empty resource still prints `(already empty, skipping)`. The final line is `Done.` and exit code is 0.

- [ ] **Step 5: Re-run dry-run to confirm idempotency**

Run:

```bash
demos/agent-gateway/scripts/clear_registry_bindings.sh --dry-run
```

Expected: every resource now prints `(already empty, skipping)`. The per-collection summaries report `would process 0 resource(s).` for the iteration counts of resources that needed clearing — actually they will report `would process N resource(s).` because the loop iterated N resources, but each one was a skip. (This is intentional — the summary counts iterations, not writes.)

- [ ] **Step 6: Verify per-type flag scoping**

Run:

```bash
demos/agent-gateway/scripts/grant_agent_mcp_egress.sh --bind-all-agents --mcp
demos/agent-gateway/scripts/clear_registry_bindings.sh --endpoints --dry-run
```

Expected: the dry-run output contains only the `--- endpoints ---` section. The mcpServers (which were just re-seeded) are NOT touched. The header `Process:` line reads `Process: endpoints` only.

Then clear the seeded mcpServers binding to leave the project clean:

```bash
demos/agent-gateway/scripts/clear_registry_bindings.sh --mcp
```

- [ ] **Step 7: If anything failed, fix and re-run**

Common failure modes and fixes:

- **`HTTP 403` from `iap.googleapis.com` `getIamPolicy`** — your principal lacks `roles/iap.settingsAdmin` on the project. Grant it: `gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="user:$(gcloud config get-value account)" --role=roles/iap.settingsAdmin`.
- **`HTTP 409` from `setIamPolicy`** — etag race. Re-run; the GET will pick up the new etag.
- **`gcloud beta ai reasoning-engines list` fails with "command not found"** — install the beta component: `gcloud components install beta`.
- **The dry-run summary line says `processed 0 resource(s)` when you expect resources to exist** — listing returned an empty array. Verify with the raw list call from the script header: `curl -sS -H "Authorization: Bearer $(gcloud auth print-access-token)" "https://agentregistry.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/${REGION}/mcpServers" | jq`.

There is nothing to commit in this task — it is verification only.

---

### Task 10: Final review and finalize

**Files:** none (verification only)

- [ ] **Step 1: Diff against the grant script for stylistic parity**

Run: `diff -u demos/agent-gateway/scripts/grant_agent_mcp_egress.sh demos/agent-gateway/scripts/clear_registry_bindings.sh | head -100`

Expected: large semantic differences (different docs, different policy logic, different dispatch), but the boilerplate (license header, `value_for`, `http_request`, `mapfile`+`jq` discovery snippet, required-command loop) should be near-identical. If a `diff` shows the boilerplate has drifted, copy from the grant script verbatim.

- [ ] **Step 2: Final shellcheck**

Run: `shellcheck demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: empty output, exit code 0.

- [ ] **Step 3: Final pre-commit**

Run: `pre-commit run --files demos/agent-gateway/scripts/clear_registry_bindings.sh`
Expected: all hooks pass with no diff.

- [ ] **Step 4: Confirm commit graph is clean**

Run: `jj log -r '@-::main+' --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' | head -20`

Expected: a sequence of small atomic commits, each with a conventional-commits-style message, leading from `main` to `@-`. If any commit message is wrong, fix with `jj describe -r <change_id> -m "..."`.

There is nothing further to commit — finalize-only.

---

## Self-review notes (informational, not part of execution)

- Spec coverage: every section of the spec maps to at least one task. Flag surface → Task 3. Discovery → Tasks 5 & 6. IAM clear → Task 4. URL roots → Tasks 5 & 6. Reuse from grant script → Tasks 3, 4, 5. Output → Task 4 (`==>` line + count) and Tasks 5/6 (per-type summary). Failure mode → Task 4 (`http_request` exits on non-2xx) and Task 9 (manual verification of common failures). Testing → Task 9.
- Type consistency: function names used in dispatch (Task 7) match definitions (`process_registry_collection` in Task 5, `process_reasoning_engines` in Task 6, `clear_policy` in Task 4, `http_request` in Task 4). The `DRY_RUN` flag is initialized in Task 3 and consumed in Tasks 4, 5, 6, 7.
- One spec gap I noticed during planning: the spec said clear-by-skip when the GET returns no `bindings` key. The implementation in Task 4 actually checks `(.bindings // []) | length == 0`, which also skips the case where `.bindings` is present but empty. That is the safer reading and is what the operator actually wants — leave as-is.
