---
name: deploy-network-lab
description: >-
  Deploys, verifies, tears down, checks prerequisites for, and describes the Google Cloud
  network lab environment (01-foundation and 02-networking) across both Network Connectivity
  Center (NCC) and Hub-and-Spoke VPC Network Peering topologies. Use when the user asks to
  deploy, set up, or spin up a network/NCC/VPC-peering lab; check or validate lab
  prerequisites and IAM permissions; describe the lab architecture or resources; verify
  VPN, BGP, NCC spoke, VPC peering, or firewall policy status; or destroy, tear down, or
  clean up a deployed lab. Don't use for authoring or refactoring Terraform module source
  code under modules/, running Docker CFT lint or integration tests via the Makefile, or
  reviewing pull request diffs.
---

# Deploy Network Lab Skill

This skill guides describing the architecture, validating prerequisites, deploying, verifying, and tearing down the two-stage Google Cloud network lab (`01-foundation` and `02-networking`).

> [!IMPORTANT]
> **Global Execution Invariants (Apply to Every Command Below)**
> 1. **Stateless Subshells (`-chdir` only)**: Never rely on `cd` or `export` persisting across tool calls. Always run from the repository root using `terraform -chdir=examples/{lab_name}/<stage>`.
> 2. **Service Account Impersonation Convention**: Throughout this runbook, `[GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}]` denotes an inline environment prefix. Include it on **every** `terraform` command (`init`, `plan`, `show`, `apply`, `output`, `destroy`) when impersonating a Service Account, and omit it when running as the current user. Similarly, pass `--impersonate-sa {sa_email}` to helper scripts and `--impersonate-service-account={sa_email}` to `gcloud` commands.
> 3. **Zero-Touch & Single-Turn Input Collection**: Use any values the user already provided in their prompt directly without re-asking. For missing values, run read-only discovery commands first (`gcloud config get-value project`, `gcloud organizations list`, `gcloud billing projects describe`) and ask the user to confirm all missing inputs in **one consolidated turn** (using `ask_question` if available in your harness, or a concise bulleted prompt).

---

## Describing the Lab Code

When the user asks to "describe this code" or "describe the network lab":
1. Read [references/architecture.md](references/architecture.md) for the complete stage breakdown, firewall/tag rule counts (`~55` foundation resources; `~224` NCC or `~220` VPC Peering networking resources), IAM matrix, and 7-step lifecycle summary.
2. Consult `README.md`, `modules/foundation/README.md`, or `modules/networking/README.md` if the user asks for specific subnet CIDRs, BGP session IPs, or firewall rule priorities.
3. Present a structured summary covering: (1) Two-Stage Architecture (`01-foundation` & `02-networking`), (2) Deployment Workflow, and (3) Provisioned Resources.

---

## Standalone Prerequisite Check

When the user asks to "check prerequisites", "check prereqs", or validate readiness before deploying:

1. **Auto-Discover Candidate Defaults**:
   ```bash
   ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null)
   DISCOVERED_ORG_ID=$(gcloud organizations list --format="value(name)" 2>/dev/null | head -n1 | sed 's|organizations/||')
   DISCOVERED_BILLING_ID=$(gcloud billing projects describe "$ACTIVE_PROJECT" --format="value(billingAccountName)" 2>/dev/null | sed 's|billingAccounts/||')
   echo "project=${ACTIVE_PROJECT} org=${DISCOVERED_ORG_ID} billing=${DISCOVERED_BILLING_ID}"
   ```

2. **Confirm Missing Inputs in One Turn**:
   Ask the user to confirm or provide any unspecified values:
   - **Topology**: `ncc` (default) or `vpc-peering`.
   - **Seed Project ID** (for hosting the GCS state bucket): Suggest `{ACTIVE_PROJECT}`.
   - **Organization ID**: Suggest `{DISCOVERED_ORG_ID}`.
   - **Billing Account ID**: Suggest `{DISCOVERED_BILLING_ID}`.
   - **Naming Prefix** *(optional)*: Must match `^[a-z0-9]{1,7}$` (defaults to `ncc` or `peer`).
   - **Execution Identity**: Current authenticated user, or Service Account email (`{sa_email}`) for impersonation.
   - **GCS State Bucket** *(optional)*: Bucket name if testing remote state access.

3. **Run [check_prereqs.py](scripts/check_prereqs.py)**:
   ```bash
   python3 .agents/skills/deploy-network-lab/scripts/check_prereqs.py \
     --topology "{topology}" \
     --project "{seed_project}" \
     --org-id "{organization_id}" \
     --billing-account "{billing_account_id}" \
     [--prefix "{prefix}"] \
     [--impersonate-sa "{sa_email}"] \
     [--state-bucket "{bucket_name}"]
   ```
   The script validates: Terraform `>= 1.5.0`, `gcloud` CLI + ADC, CLI **and** ADC Service Account impersonation (`iamcredentials.googleapis.com`), seed project `ACTIVE` state, topology-specific Organization IAM roles (including `orgSecurityPolicyAdmin`, `orgSecurityResourceAdmin`, `tagAdmin`, `tagUser`, and `networkconnectivity.admin` for NCC), `prefix` format & folder collision check, Billing Account `OPEN` status + `roles/billing.user` for the execution identity, and GCS bucket access.

4. **Present Readiness Report & Remediations**:
   Summarize `PASS`/`WARNING`/`FAIL` results and include the exact copy-pasteable `gcloud` remediation commands output by `check_prereqs.py` for any failures. **Do not** create lab directories or Terraform resources during a standalone prerequisite check.

---

## Deployment Workflow

### 1. Discover Defaults, Confirm Inputs & Validate Prerequisites
1. Run the auto-discovery snippet from **Standalone Prerequisite Check (Step 1)** and inspect required Terraform variables if needed via [find_vars.py](scripts/find_vars.py):
   ```bash
   python3 .agents/skills/deploy-network-lab/scripts/find_vars.py examples/ncc/01-foundation/variables.tf examples/ncc/02-networking/variables.tf
   ```
2. In **a single consolidated turn**, confirm any missing parameters with the user:
   - **`{topology}`**: `ncc` (`examples/ncc`, default) or `vpc-peering` (`examples/vpc-peering`).
   - **`{lab_name}`**: Local workspace folder under `examples/` (e.g., `nwklab` or `peeringlab`; never modify `examples/ncc` or `examples/vpc-peering` in place).
   - **`{prefix}`**: **1–7 lowercase alphanumeric characters (`^[a-z0-9]{1,7}$`), no hyphens** (defaults to `ncc` for `examples/ncc` and `peer` for `examples/vpc-peering`). If deploying a second lab in the same org, choose a distinct prefix so `fldr-{prefix}-network-lab` and `{prefix}-workload` tag keys do not collide.
   - **`{organization_id}`** and **`{billing_account_id}`** (stripped of `organizations/` and `billingAccounts/`).
   - **`{seed_project}`** and **`{bucket_name}`** (suggest `{seed_project}-tfstate` or `nwklab-tfstate-{random_suffix}`).
   - **Execution Identity**: Current user vs. Service Account impersonation (`{sa_email}`). If impersonation is chosen, `{sa_email}` is mandatory before proceeding.
3. Run [check_prereqs.py](scripts/check_prereqs.py) (omit `--state-bucket` only if the bucket will be created in Step 2, or pass `--resume` if resuming an existing lab):
   ```bash
   python3 .agents/skills/deploy-network-lab/scripts/check_prereqs.py \
     --topology "{topology}" \
     --project "{seed_project}" \
     --org-id "{organization_id}" \
     --billing-account "{billing_account_id}" \
     --prefix "{prefix}" \
     [--impersonate-sa "{sa_email}"] \
     [--state-bucket "{bucket_name}"] \
     [--resume]
   ```
   Stop and help the user resolve any critical `FAIL` items (other than a not-yet-created state bucket, which Step 2 creates) before continuing.

### 2. Initialize Lab Directory & Remote State Bucket
1. Ensure the GCS state bucket exists (using explicit `--location=us-east4`, `--uniform-bucket-level-access`, and `--public-access-prevention` to satisfy enterprise Org Policies):
   ```bash
   gcloud storage buckets describe gs://{bucket_name} --project={seed_project} >/dev/null 2>&1 || \
     gcloud storage buckets create gs://{bucket_name} --project={seed_project} --location=us-east4 --uniform-bucket-level-access --public-access-prevention
   ```
   If using Service Account impersonation (`{sa_email}`), verify the SA can access `gs://{bucket_name}` (and if you just created the bucket as the current user, grant bucket state permissions to `{sa_email}`):
   ```bash
   gcloud storage buckets describe gs://{bucket_name} --impersonate-service-account={sa_email} >/dev/null 2>&1 || {
     gcloud storage buckets add-iam-policy-binding gs://{bucket_name} --member="serviceAccount:{sa_email}" --role="roles/storage.legacyBucketReader"
     gcloud storage buckets add-iam-policy-binding gs://{bucket_name} --member="serviceAccount:{sa_email}" --role="roles/storage.objectAdmin"
   }
   ```
2. Copy the chosen template (`examples/ncc` or `examples/vpc-peering`) into `examples/{lab_name}` without nesting directories:
   - **New lab**:
     ```bash
     mkdir -p examples/{lab_name} && cp -r examples/{topology}/. examples/{lab_name}/
     ```
   - **Smart Resume** (if `examples/{lab_name}` already exists and the user wants to resume): Ensure `backend.tf` and `terraform.tfvars` match in both stages, run `[GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation init`, and check `[GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation output -raw base_folder_id`. If populated, skip Step 3 and proceed directly to Step 4.
3. Update `backend.tf` in **both** stages with `{bucket_name}` and lab-namespaced state prefixes so multiple labs never collide:
   - `examples/{lab_name}/01-foundation/backend.tf` -> `bucket = "{bucket_name}"`, `prefix = "{lab_name}/foundation"`
   - `examples/{lab_name}/02-networking/backend.tf` -> `bucket = "{bucket_name}"`, `prefix = "{lab_name}/networking"`
4. Write identical `terraform.tfvars` files in **both** `examples/{lab_name}/01-foundation/` and `examples/{lab_name}/02-networking/`:
   > [!WARNING]
   > `prefix` **must be identical** in both stages because `02-networking` discovers `01-foundation` folders via `fldr-${var.prefix}-*`.
   ```hcl
   organization_id    = "{organization_id}"
   billing_account_id = "{billing_account_id}"
   prefix             = "{prefix}"
   ```

### 3. Deploy Stage 1 (`01-foundation`)
1. Initialize, plan, and summarize changes with [summarize_plan.py](scripts/summarize_plan.py):
   ```bash
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation init
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation plan -out=tfplan
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation show -json tfplan > examples/{lab_name}/01-foundation/plan.json
   python3 .agents/skills/deploy-network-lab/scripts/summarize_plan.py examples/{lab_name}/01-foundation/plan.json
   ```
2. **Safety Gate**: Verify `summarize_plan.py` reports expected creations (~55 resources) and **zero unexpected `DELETE` or `REPLACE` actions** (if any destructive changes appear, pause and ask the user before applying).
3. Apply the saved plan, remove temporary plan artifacts, and capture `{numeric_folder_id}`:
   ```bash
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation apply tfplan
   rm -f examples/{lab_name}/01-foundation/tfplan examples/{lab_name}/01-foundation/plan.json
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation output -raw base_folder_id | sed 's|folders/||'
   ```

### 4. Check & Reset `compute.restrictVpnPeerIPs` Organization Policy
HA VPN tunnels in `02-networking` fail with `412 Precondition Failed` if the organization restricts VPN peer IPs on the lab folder.
1. Inspect the effective policy on `{numeric_folder_id}` (pass `--impersonate-service-account={sa_email}` when impersonating; **do not** run the `org_policy_reset_command` Terraform output verbatim when impersonating because that output omits `--impersonate-service-account`):
   ```bash
   gcloud org-policies describe compute.restrictVpnPeerIPs --folder={numeric_folder_id} --effective --format="json" [--impersonate-service-account={sa_email}]
   ```
2. **Conditional Reset & Cache Propagation**:
   - **If the effective policy already has `allowAll: true`**: Skip the reset and **skip the 45-second wait** — proceed immediately to Step 5.
   - **If the effective policy restricts peer IPs (`denyAll` or `values` list)**: Reset it on the folder, verify `allowAll`, and wait 45 seconds for regional Compute Engine policy enforcement caches (`compute.googleapis.com`) to update asynchronously:
     ```bash
     gcloud org-policies reset compute.restrictVpnPeerIPs --folder={numeric_folder_id} [--impersonate-service-account={sa_email}]
     gcloud org-policies describe compute.restrictVpnPeerIPs --folder={numeric_folder_id} --effective --format="json" [--impersonate-service-account={sa_email}]
     sleep 45
     ```

### 5. Deploy Stage 2 (`02-networking`)
1. Initialize, plan, and summarize changes:
   ```bash
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/02-networking init
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/02-networking plan -out=tfplan
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/02-networking show -json tfplan > examples/{lab_name}/02-networking/plan.json
   python3 .agents/skills/deploy-network-lab/scripts/summarize_plan.py examples/{lab_name}/02-networking/plan.json
   ```
2. **Safety Gate**: Confirm ~224 resources (`ncc`) or ~220 resources (`vpc-peering`) to create and **zero unexpected `DELETE` or `REPLACE` actions** (if destructive changes appear, pause for user confirmation).
3. Apply `tfplan` and clean up temporary plan files:
   ```bash
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/02-networking apply tfplan
   rm -f examples/{lab_name}/02-networking/tfplan examples/{lab_name}/02-networking/plan.json
   ```
   > [!TIP]
   > **Handling Partial-Apply Transient Errors**: If `apply` hits a transient Cloud Router BGP concurrency error (`resourceNotReady`) or delayed Org Policy cache (`restrictVpnPeerIPs`), wait 30s and **re-run `plan -out=tfplan` -> `summarize_plan.py` -> `apply tfplan`** (do not re-apply the old `tfplan` file, which becomes stale once Terraform state advances).

---

## Verifying the Deployment

*(If invoked standalone in a new session, list subdirectories under `examples/` excluding `ncc` and `vpc-peering` to identify `{lab_name}`, and confirm if SA impersonation is needed.)*

Run [verify_deployment.py](scripts/verify_deployment.py) from the workspace root with `--retries` to poll while IKEv2/BGP sessions exchange routes:
```bash
python3 .agents/skills/deploy-network-lab/scripts/verify_deployment.py \
  --lab-dir examples/{lab_name} \
  --retries 3 \
  --retry-delay 30 \
  [--impersonate-sa "{sa_email}"]
```
Confirm all checks pass:
- **16 HA VPN Tunnels** (`4` in `on-prem`, `8` in `prod-transit`, `4` in `prod-host`) are `ESTABLISHED`.
- **6 BGP VPN Cloud Routers** (`router-vpn-*`) have `Established` sessions with `learned routes > 0`.
- **Inter-VPC Connectivity**: All **8 NCC Spokes** (`4` Hybrid VPN + `4` VPC) are `ACTIVE` (`enable_ncc = true`), **or** all **6 VPC Network Peerings** are `ACTIVE` (`enable_vpc_peering = true`).
- **Firewall Policies**: The L1 folder **Hierarchical Firewall Policy** and all **6 Global Network Firewall Policies** are associated and active.

---

## Tearing Down (Cleanup)

*(If invoked standalone in a new session, identify `examples/{lab_name}` and confirm with the user before destroying any infrastructure.)*

1. **Scan for Teardown Blockers** with [check_teardown.py](scripts/check_teardown.py) (checks unmanaged VMs, classic firewall rules, forwarding rules / PSC endpoints, unmanaged VPC/PSA peerings, private Cloud DNS zones, active `GCE_FIREWALL` Secure Tag bindings on folders/projects/VPCs, project liens via CRM REST API, extra Shared VPC attachments, and unmanaged projects inside lab folders):
   ```bash
   python3 .agents/skills/deploy-network-lab/scripts/check_teardown.py \
     --lab-dir examples/{lab_name} \
     [--impersonate-sa "{sa_email}"]
   ```
   - If standalone blockers (VMs, manual classic firewall rules, forwarding rules, Secure Tag bindings, or project liens) are reported, ask the user before running `--clean`:
     ```bash
     python3 .agents/skills/deploy-network-lab/scripts/check_teardown.py \
       --lab-dir examples/{lab_name} \
       --clean \
       [--impersonate-sa "{sa_email}"]
     ```
2. **Destroy Stages in Reverse Order** (`02-networking` first, then `01-foundation`):
   ```bash
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/02-networking destroy -auto-approve
   ```
   *(If `02-networking` destroy encounters a transient Cloud Router `resourceNotReady` error while detaching multiple BGP peers concurrently, re-run the `02-networking` `destroy -auto-approve` command.)*
   Once `02-networking` succeeds, destroy `01-foundation`:
   ```bash
   [GOOGLE_IMPERSONATE_SERVICE_ACCOUNT={sa_email}] terraform -chdir=examples/{lab_name}/01-foundation destroy -auto-approve
   ```
3. **Optional State & Workspace Cleanup** (ask the user first):
   - Remove only this lab's state prefix (safe when sharing a state bucket across labs):
     ```bash
     gcloud storage rm --recursive gs://{bucket_name}/{lab_name}/ [--impersonate-service-account={sa_email}]
     ```
   - Or remove the entire bucket if dedicated solely to this lab:
     ```bash
     gcloud storage rm --recursive gs://{bucket_name} [--impersonate-service-account={sa_email}]
     ```
   - Remove the local lab directory:
     ```bash
     rm -rf examples/{lab_name}
     ```
