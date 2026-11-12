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

import argparse
from collections import defaultdict
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request

PREFIX_PATTERN = re.compile(r"^[a-z0-9]{1,7}$")


def run_command(cmd):
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        return result.stdout.strip(), None
    except subprocess.CalledProcessError as e:
        return None, e.stderr.strip()
    except FileNotFoundError:
        return None, f"Command not found: {cmd[0]}"


def check_terraform():
    print("Checking Terraform...")
    stdout, err = run_command(["terraform", "version", "-json"])
    if err:
        return False, f"Failed to run terraform: {err}"

    try:
        data = json.loads(stdout)
        version_str = data.get("terraform_version", "")
        print(f"  Found Terraform version: {version_str}")
        match = re.match(r"^(\d+)\.(\d+)\.(\d+)", version_str)
        if match:
            major, minor, _ = map(int, match.groups())
            if (major > 1) or (major == 1 and minor >= 5):
                return True, f"Terraform version {version_str} is >= 1.5"
            return False, f"Terraform version {version_str} is < 1.5. Please upgrade."
        return False, f"Could not parse Terraform version string: {version_str}"
    except Exception as e:
        return False, f"Failed to parse terraform version output: {e}"


def check_gcloud():
    print("Checking gcloud SDK...")
    _, err = run_command(["gcloud", "version", "--format=json"])
    if err:
        return False, f"gcloud SDK not found or failed to run: {err}"
    print("  gcloud SDK is installed.")
    return True, "gcloud SDK is installed"


def check_gcloud_auth():
    print("Checking gcloud authentication...")
    account, err = run_command(["gcloud", "config", "get-value", "account"])
    if err or not account:
        return False, "No active gcloud account found. Run 'gcloud auth login'."
    print(f"  Active gcloud account: {account}")

    print("Checking Application Default Credentials (ADC)...")
    adc_token, adc_err = run_command(
        ["gcloud", "auth", "application-default", "print-access-token"]
    )
    if adc_err or not adc_token:
        return (
            False,
            f"ADC is not configured or invalid. Run 'gcloud auth application-default login'. Error: {adc_err}",
        )
    print("  ADC is configured.")
    return True, f"Authenticated as {account} with ADC configured."


def _generate_impersonated_token_via_adc(sa_email):
    adc_token, adc_err = run_command(
        ["gcloud", "auth", "application-default", "print-access-token"]
    )
    if adc_err or not adc_token:
        return False, f"Could not read ADC token: {adc_err}"

    url = (
        f"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/"
        f"{sa_email}:generateAccessToken"
    )
    payload = json.dumps(
        {"scope": ["https://www.googleapis.com/auth/cloud-platform"]}
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {adc_token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("accessToken"):
                return True, None
            return False, "IAM Credentials API did not return an accessToken."
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return False, f"HTTP {e.code} via ADC: {body}"
    except Exception as e:
        return False, str(e)


def check_impersonation(sa_email):
    if not sa_email:
        return True, "No impersonation requested."

    print(f"Checking impersonation permissions for {sa_email}...")
    _, cli_err = run_command(
        [
            "gcloud",
            "auth",
            "print-access-token",
            f"--impersonate-service-account={sa_email}",
        ]
    )
    if cli_err:
        return (
            False,
            f"Failed to impersonate {sa_email} via gcloud CLI. Ensure you have 'roles/iam.serviceAccountTokenCreator' on the SA. Error: {cli_err}",
        )

    adc_ok, adc_err = _generate_impersonated_token_via_adc(sa_email)
    if not adc_ok:
        return (
            False,
            f"gcloud CLI impersonation succeeded, but Application Default Credentials (ADC) failed to impersonate {sa_email} "
            f"(Terraform uses ADC). Re-run 'gcloud auth application-default login' with the same authorized account. Details: {adc_err}",
        )

    print("  Impersonation verified for both gcloud CLI and Terraform ADC.")
    return True, f"Successfully impersonated {sa_email} (CLI + ADC)"


def test_org_iam_permissions(clean_org_id, permissions, impersonated_sa=None):
    token_cmd = ["gcloud", "auth", "print-access-token"]
    if impersonated_sa:
        token_cmd.append(f"--impersonate-service-account={impersonated_sa}")
    token, err = run_command(token_cmd)
    if err or not token:
        return None, f"Could not obtain access token for permission check: {err}"

    url = f"https://cloudresourcemanager.googleapis.com/v1/organizations/{clean_org_id}:testIamPermissions"
    payload = json.dumps({"permissions": permissions}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return set(data.get("permissions", [])), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}"
    except Exception as e:
        return None, str(e)


def get_required_org_roles(topology="ncc"):
    roles = [
        (
            "roles/resourcemanager.folderAdmin",
            "Folder Admin",
            "resourcemanager.folders.create",
        ),
        (
            "roles/resourcemanager.projectCreator",
            "Project Creator",
            "resourcemanager.projects.create",
        ),
        (
            "roles/resourcemanager.projectDeleter",
            "Project Deleter",
            None,
        ),
        (
            "roles/compute.xpnAdmin",
            "Shared VPC Admin",
            "compute.organizations.enableXpnHost",
        ),
        (
            "roles/compute.networkAdmin",
            "Compute Network Admin",
            None,
        ),
        (
            "roles/compute.orgSecurityPolicyAdmin",
            "Compute Organization Security Policy Admin",
            "compute.firewallPolicies.create",
        ),
        (
            "roles/compute.orgSecurityResourceAdmin",
            "Compute Organization Resource Admin",
            "compute.organizations.setSecurityPolicy",
        ),
        (
            "roles/resourcemanager.tagAdmin",
            "Tag Administrator",
            "resourcemanager.tagKeys.create",
        ),
        (
            "roles/resourcemanager.tagUser",
            "Tag User",
            "resourcemanager.tagValues.list",
        ),
    ]
    if topology == "ncc":
        roles.append(
            (
                "roles/networkconnectivity.admin",
                "Network Connectivity Center Admin",
                None,
            )
        )
    roles.append(
        (
            "roles/orgpolicy.policyAdmin",
            "Organization Policy Admin",
            "orgpolicy.policy.set",
        )
    )
    return roles


def check_org_iam_roles(org_id, active_account, impersonated_sa, topology="ncc"):
    if not org_id:
        return True, "Skipping Organization IAM role checks.", []

    clean_org_id = org_id.replace("organizations/", "").strip()
    target_identity = impersonated_sa if impersonated_sa else active_account
    if not target_identity:
        return False, "Could not determine target identity for IAM check.", []

    required_roles = get_required_org_roles(topology=topology)

    print(
        f"Checking Organization IAM roles ({topology} topology) on organization {clean_org_id} for {target_identity}..."
    )

    # Test effective permissions via testIamPermissions (resolves Google Groups, custom roles, and roles/owner)
    testable_perms = [perm for _, _, perm in required_roles if perm]
    granted_perms, _ = test_org_iam_permissions(
        clean_org_id, testable_perms, impersonated_sa
    )

    cmd = ["gcloud", "organizations", "get-iam-policy", clean_org_id, "--format=json"]
    if impersonated_sa:
        cmd.append(f"--impersonate-service-account={impersonated_sa}")

    stdout, err = run_command(cmd)
    if err and impersonated_sa:
        # Reading the org IAM policy to inspect direct bindings can fall back to the active user
        # because testIamPermissions above already tested the impersonated SA's effective permissions.
        stdout, err = run_command(
            ["gcloud", "organizations", "get-iam-policy", clean_org_id, "--format=json"]
        )

    role_to_members = defaultdict(list)
    if not err and stdout:
        try:
            policy = json.loads(stdout)
            for b in policy.get("bindings", []):
                if isinstance(b, dict) and b.get("role"):
                    role_to_members[b["role"]].extend(b.get("members", []))
        except Exception as e:
            return None, f"Failed to parse IAM policy: {e}", []
    elif granted_perms is None:
        return (
            None,
            f"Could not retrieve organization IAM policy or test permissions. Error: {err}",
            [],
        )

    user_member = f"user:{target_identity}"
    sa_member = f"serviceAccount:{target_identity}"
    has_broader_role = any(
        user_member in role_to_members.get(r, [])
        or sa_member in role_to_members.get(r, [])
        for r in ("roles/owner",)
    )

    unconfirmed_roles = []
    missing_role_ids = []
    missing_effective_perms = []
    for role_id, role_label, test_perm in required_roles:
        members = role_to_members.get(role_id, [])
        direct_match = (user_member in members) or (sa_member in members)
        perm_match = (
            granted_perms is not None and test_perm and test_perm in granted_perms
        )

        if direct_match:
            print(f"  [+] {role_label} ({role_id}): CONFIRMED (direct binding)")
        elif perm_match or has_broader_role:
            print(
                f"  [+] {role_label} ({role_id}): CONFIRMED (effective permission verified)"
            )
        elif (
            granted_perms is not None
            and test_perm
            and test_perm not in granted_perms
        ):
            print(
                f"  [-] {role_label} ({role_id}): MISSING effective permission '{test_perm}'"
            )
            missing_role_ids.append(role_id)
            missing_effective_perms.append(f"{role_id} ({test_perm})")
        else:
            print(
                f"  [!] {role_label} ({role_id}): Not directly bound to {target_identity} (may be inherited via a Google Group)"
            )
            unconfirmed_roles.append(role_id)

    if missing_effective_perms:
        return (
            False,
            f"Missing required organization permissions for {target_identity}: {', '.join(missing_effective_perms)}",
            missing_role_ids,
        )
    if not unconfirmed_roles:
        return (
            True,
            f"Confirmed all required organization roles/permissions for {target_identity}",
            [],
        )
    return (
        None,
        (
            f"Verified core organization permissions, but could not directly confirm {', '.join(unconfirmed_roles)} "
            f"for {target_identity} (may be inherited via a Google Group)."
        ),
        [],
    )


def check_prefix_collisions(prefix, org_id, impersonated_sa=None, allow_existing=False):
    if not prefix:
        return True, "Skipping prefix validation.", []

    clean_prefix = prefix.strip()
    if not PREFIX_PATTERN.match(clean_prefix):
        return (
            False,
            f"Invalid prefix '{clean_prefix}': must be 1 to 7 lowercase alphanumeric characters (^[a-z0-9]{{1,7}}$) with no hyphens.",
            [
                "# Choose a 1-7 character lowercase alphanumeric prefix (e.g., 'ncc', 'peer', 'lab01')."
            ],
        )

    if not org_id or allow_existing:
        return True, f"Prefix '{clean_prefix}' format is valid.", []

    clean_org_id = org_id.replace("organizations/", "").strip()
    print(
        f"Checking for existing lab collisions with prefix '{clean_prefix}' in organization {clean_org_id}..."
    )
    folder_name = f"fldr-{clean_prefix}-network-lab"
    cmd = [
        "gcloud",
        "resource-manager",
        "folders",
        "list",
        f"--organization={clean_org_id}",
        f"--filter=displayName={folder_name}",
        "--format=json",
    ]
    if impersonated_sa:
        cmd.append(f"--impersonate-service-account={impersonated_sa}")

    stdout, err = run_command(cmd)
    if not err and stdout:
        try:
            folders = json.loads(stdout)
            if folders:
                fid = folders[0].get("name", "unknown")
                return (
                    None,
                    f"Folder '{folder_name}' ({fid}) already exists under organizations/{clean_org_id}. "
                    f"Use a distinct prefix (<=7 chars) if deploying a new lab side-by-side, or reuse the existing lab directory to resume.",
                    [],
                )
        except Exception:
            pass

    print(f"  [+] Prefix '{clean_prefix}' is valid and has no top-level folder collision.")
    return True, f"Prefix '{clean_prefix}' is valid and available", []


def check_billing_account(billing_account_id, target_identity, member_prefix, impersonated_sa):
    if not billing_account_id:
        return True, "Skipping Billing Account check.", []

    clean_id = billing_account_id.replace("billingAccounts/", "").strip()
    print(f"Checking Billing Account {clean_id} for {target_identity}...")
    cmd = ["gcloud", "billing", "accounts", "describe", clean_id, "--format=json"]
    if impersonated_sa:
        cmd.append(f"--impersonate-service-account={impersonated_sa}")

    # Do NOT fall back to the active user when impersonating: the execution identity itself
    # must hold roles/billing.user to link newly created lab projects in 01-foundation and 02-networking.
    stdout, err = run_command(cmd)
    if err:
        remedies = [
            f"# Grant Billing Account User role on {clean_id} to {target_identity}:\n"
            f"gcloud billing accounts add-iam-policy-binding {clean_id} \\\n"
            f'  --member="{member_prefix}:{target_identity}" \\\n'
            f'  --role="roles/billing.user"'
        ]
        return (
            False,
            f"Execution identity '{target_identity}' cannot access billing account {clean_id} (ensure roles/billing.user is granted). Error: {err}",
            remedies,
        )

    try:
        data = json.loads(stdout)
        is_open = data.get("open", False)
        display_name = data.get("displayName", clean_id)
        if is_open:
            print(
                f"  [+] Billing Account '{display_name}' ({clean_id}) is OPEN and accessible by {target_identity}."
            )
            return True, f"Billing account {clean_id} is open and accessible", []
        return (
            False,
            f"Billing account '{display_name}' ({clean_id}) is CLOSED.",
            [
                f"# Reopen billing account {clean_id} in Google Cloud Console or select an open billing account:\n"
                f"# https://console.cloud.google.com/billing/{clean_id}"
            ],
        )
    except Exception as e:
        return None, f"Failed to parse billing account output: {e}", []


def check_project(project_id, impersonated_sa):
    if not project_id:
        return True, "Skipping Project existence check.", []

    clean_proj = project_id.strip()
    target_desc = impersonated_sa if impersonated_sa else "current user"
    print(f"Checking seed Google Cloud Project '{clean_proj}'...")
    cmd = ["gcloud", "projects", "describe", clean_proj, "--format=json"]
    if impersonated_sa:
        cmd.append(f"--impersonate-service-account={impersonated_sa}")

    stdout, err = run_command(cmd)
    checked_via_user_fallback = False
    if err and impersonated_sa:
        # In least-privilege setups, an impersonated SA may have bucket-level roles/storage.objectAdmin
        # without project-level resourcemanager.projects.get on the seed project. Check as active user
        # strictly to confirm the seed project exists and is ACTIVE without claiming SA project access.
        user_stdout, user_err = run_command(
            ["gcloud", "projects", "describe", clean_proj, "--format=json"]
        )
        if not user_err and user_stdout:
            stdout, err = user_stdout, None
            checked_via_user_fallback = True

    if err:
        remedies = [
            f"# Verify the seed project ID is spelled correctly or create the project:\n"
            f"gcloud projects create {clean_proj}"
        ]
        return (
            False,
            f"Project '{clean_proj}' does not exist or cannot be accessed by {target_desc}. Error: {err}",
            remedies,
        )

    try:
        data = json.loads(stdout)
        lifecycle = data.get("lifecycleState", "UNKNOWN")
        name = data.get("name", clean_proj)
        if lifecycle == "ACTIVE":
            if checked_via_user_fallback:
                print(
                    f"  [+] Project '{name}' ({clean_proj}) is ACTIVE (verified via active user; SA lacks project-level describe, ensure bucket-level access)."
                )
            else:
                print(
                    f"  [+] Project '{name}' ({clean_proj}) is ACTIVE and accessible by {target_desc}."
                )
            return True, f"Project '{clean_proj}' is active", []

        remedies = [
            f"# Project '{clean_proj}' is in lifecycle state '{lifecycle}'. Restore it or use an ACTIVE project:\n"
            f"gcloud projects undelete {clean_proj}"
        ]
        return (
            False,
            f"Project '{clean_proj}' is in state '{lifecycle}' (Expected ACTIVE).",
            remedies,
        )
    except Exception as e:
        return None, f"Failed to parse project describe output: {e}", []


def check_state_bucket(bucket_name, target_project, impersonated_sa, location="us-east4"):
    if not bucket_name:
        return True, "Skipping GCS State Bucket check.", []

    clean_bucket = bucket_name.replace("gs://", "").strip().rstrip("/")
    target_desc = impersonated_sa if impersonated_sa else "current user"
    print(f"Checking GCS State Bucket gs://{clean_bucket} access for {target_desc}...")
    cmd = [
        "gcloud",
        "storage",
        "buckets",
        "describe",
        f"gs://{clean_bucket}",
        "--format=json",
    ]
    if impersonated_sa:
        cmd.append(f"--impersonate-service-account={impersonated_sa}")

    _, err = run_command(cmd)
    proj = target_project or "<PROJECT_ID>"
    remedies = []
    if err:
        remedies.append(
            f"# Create GCS state bucket (if it does not exist) with uniform bucket-level access and public access prevention:\n"
            f"gcloud storage buckets create gs://{clean_bucket} --project={proj} --location={location} "
            f"--uniform-bucket-level-access --public-access-prevention"
        )
        if impersonated_sa:
            remedies.append(
                f"# Grant Storage Legacy Bucket Reader & Storage Object Admin roles on gs://{clean_bucket} to the Service Account:\n"
                f"gcloud storage buckets add-iam-policy-binding gs://{clean_bucket} "
                f'--member="serviceAccount:{impersonated_sa}" --role="roles/storage.legacyBucketReader"\n'
                f"gcloud storage buckets add-iam-policy-binding gs://{clean_bucket} "
                f'--member="serviceAccount:{impersonated_sa}" --role="roles/storage.objectAdmin"'
            )
        return (
            False,
            f"Cannot access bucket gs://{clean_bucket} as {target_desc}. Error: {err}",
            remedies,
        )

    print(f"  [+] Bucket gs://{clean_bucket} is accessible by {target_desc}.")
    return True, f"Bucket gs://{clean_bucket} is accessible", []


def main():
    parser = argparse.ArgumentParser(
        description="Check prerequisites for deploying network lab."
    )
    parser.add_argument(
        "--project",
        help="Target seed Google Cloud project ID (e.g. for hosting the GCS state bucket)",
    )
    parser.add_argument(
        "--impersonate-sa", help="Service Account email to impersonate"
    )
    parser.add_argument(
        "--org-id",
        help="Organization ID to check required Organization IAM roles",
    )
    parser.add_argument(
        "--billing-account",
        help="Billing Account ID to verify open status and roles/billing.user access",
    )
    parser.add_argument(
        "--state-bucket",
        help="Optional GCS bucket name to verify Terraform remote state access",
    )
    parser.add_argument(
        "--bucket-location",
        default="us-east4",
        help="GCS bucket location for remediation commands (default: us-east4)",
    )
    parser.add_argument(
        "--topology",
        choices=["ncc", "vpc-peering"],
        default="ncc",
        help="Lab topology being deployed: 'ncc' (default) or 'vpc-peering'",
    )
    parser.add_argument(
        "--prefix",
        help="Optional 1-7 character lowercase alphanumeric naming prefix to validate and check for collisions",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Allow existing lab folders when resuming an existing deployment",
    )
    args = parser.parse_args()

    success = True
    remediations = []

    tf_ok, tf_msg = check_terraform()
    print(f"  Status: {'PASS' if tf_ok else 'FAIL'} - {tf_msg}\n")
    if not tf_ok:
        success = False
        remediations.append(
            "# Install or upgrade Terraform to version >= 1.5.0:\n"
            "# https://developer.hashicorp.com/terraform/install"
        )

    gc_ok, gc_msg = check_gcloud()
    print(f"  Status: {'PASS' if gc_ok else 'FAIL'} - {gc_msg}\n")
    if not gc_ok:
        remediations.append(
            "# Install the Google Cloud SDK (gcloud CLI):\n"
            "# https://cloud.google.com/sdk/docs/install"
        )
        print("Some prerequisites FAILED. Please install gcloud SDK before continuing.")
        sys.exit(1)

    auth_ok, auth_msg = check_gcloud_auth()
    print(f"  Status: {'PASS' if auth_ok else 'FAIL'} - {auth_msg}\n")
    if not auth_ok:
        remediations.append(
            "# Authenticate gcloud CLI and Application Default Credentials:\n"
            "gcloud auth login\n"
            "gcloud auth application-default login"
        )
        print(
            "Some prerequisites FAILED. Please authenticate gcloud and ADC before continuing."
        )
        sys.exit(1)

    active_account, _ = run_command(["gcloud", "config", "get-value", "account"])
    active_project, _ = run_command(["gcloud", "config", "get-value", "project"])
    target_project = args.project if args.project else active_project
    target_identity = args.impersonate_sa if args.impersonate_sa else active_account
    member_prefix = "serviceAccount" if args.impersonate_sa else "user"

    if args.impersonate_sa:
        imp_ok, imp_msg = check_impersonation(args.impersonate_sa)
        print(f"  Status: {'PASS' if imp_ok else 'FAIL'} - {imp_msg}\n")
        if not imp_ok:
            success = False
            if active_account:
                remediations.append(
                    f"# Grant Service Account Token Creator on {args.impersonate_sa} to {active_account} (and ensure ADC uses {active_account}):\n"
                    f"gcloud iam service-accounts add-iam-policy-binding {args.impersonate_sa} \\\n"
                    f'  --member="user:{active_account}" \\\n'
                    f'  --role="roles/iam.serviceAccountTokenCreator"\n'
                    f"gcloud auth application-default login"
                )

    if target_project:
        proj_ok, proj_msg, proj_remedies = check_project(
            target_project, args.impersonate_sa
        )
        if proj_ok is True:
            print(f"  Status: PASS - {proj_msg}\n")
        elif proj_ok is False:
            print(f"  Status: FAIL - {proj_msg}\n")
            success = False
            remediations.extend(proj_remedies)
        else:
            print(f"  Status: WARNING - {proj_msg}\n")

    if args.org_id:
        clean_org_id = args.org_id.replace("organizations/", "").strip()
        op_ok, op_msg, missing_roles = check_org_iam_roles(
            args.org_id,
            active_account,
            args.impersonate_sa,
            topology=args.topology,
        )
        if op_ok is True:
            print(f"  Status: PASS - {op_msg}\n")
        elif op_ok is False:
            print(f"  Status: FAIL - {op_msg}\n")
            success = False
            roles_to_grant = missing_roles or [
                r[0] for r in get_required_org_roles(topology=args.topology)
            ]
            roles_str = " \\\n  ".join(roles_to_grant)
            remediations.append(
                f"# Grant missing Organization IAM roles on organization {clean_org_id} to {target_identity}:\n"
                f"for ROLE in {roles_str}; do\n"
                f"  gcloud organizations add-iam-policy-binding {clean_org_id} \\\n"
                f'    --member="{member_prefix}:{target_identity}" \\\n'
                f'    --role="$ROLE"\n'
                f"done"
            )
        else:
            print(f"  Status: WARNING - {op_msg}\n")

    if args.prefix:
        pfx_ok, pfx_msg, pfx_remedies = check_prefix_collisions(
            args.prefix,
            args.org_id,
            impersonated_sa=args.impersonate_sa,
            allow_existing=args.resume,
        )
        if pfx_ok is True:
            print(f"  Status: PASS - {pfx_msg}\n")
        elif pfx_ok is False:
            print(f"  Status: FAIL - {pfx_msg}\n")
            success = False
            remediations.extend(pfx_remedies)
        else:
            print(f"  Status: WARNING - {pfx_msg}\n")

    if args.billing_account:
        ba_ok, ba_msg, ba_remedies = check_billing_account(
            args.billing_account,
            target_identity,
            member_prefix,
            args.impersonate_sa,
        )
        if ba_ok is True:
            print(f"  Status: PASS - {ba_msg}\n")
        elif ba_ok is False:
            print(f"  Status: FAIL - {ba_msg}\n")
            success = False
            remediations.extend(ba_remedies)
        else:
            print(f"  Status: WARNING - {ba_msg}\n")

    if args.state_bucket:
        sb_ok, sb_msg, sb_remedies = check_state_bucket(
            args.state_bucket,
            target_project,
            args.impersonate_sa,
            location=args.bucket_location,
        )
        print(f"  Status: {'PASS' if sb_ok else 'FAIL'} - {sb_msg}\n")
        if not sb_ok:
            success = False
            remediations.extend(sb_remedies)

    if remediations:
        print("============================================================")
        print("REMEDIATION COMMANDS (Copy & Paste to Resolve Failures):")
        print("============================================================")
        for r in remediations:
            print(r)
            print()
        print("============================================================\n")

    if success:
        print("All critical prerequisites PASSED.")
        sys.exit(0)
    else:
        print(
            "Some prerequisites FAILED. Please resolve them using the commands above before deploying."
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
