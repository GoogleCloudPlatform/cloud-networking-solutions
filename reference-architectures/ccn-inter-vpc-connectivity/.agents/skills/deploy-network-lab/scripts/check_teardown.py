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
from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def run_command(cmd, cwd=None, impersonate_sa=None):
    env = os.environ.copy()
    if impersonate_sa:
        env["GOOGLE_IMPERSONATE_SERVICE_ACCOUNT"] = impersonate_sa
        env["CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT"] = impersonate_sa
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
            cwd=cwd,
            env=env,
        )
        return result.stdout.strip(), None
    except subprocess.CalledProcessError as e:
        return None, e.stderr.strip()
    except FileNotFoundError:
        return None, f"Command not found: {cmd[0]}"


def _is_not_found_or_disabled(err_str, allow_service_disabled=False):
    if not err_str:
        return False
    lower = err_str.lower()
    not_found_markers = (
        "not found",
        "not_found",
        "http 404",
        "code: 404",
        "project invalid",
        "deleted",
    )
    if any(m in lower for m in not_found_markers):
        return True
    if allow_service_disabled:
        disabled_markers = (
            "service_disabled",
            "has not been used in project",
            "api has not been enabled",
            "is disabled",
        )
        if any(m in lower for m in disabled_markers):
            return True
    return False


def get_access_token(impersonate_sa=None):
    cmd = ["gcloud", "auth", "print-access-token"]
    if impersonate_sa:
        cmd.append(f"--impersonate-service-account={impersonate_sa}")
    return run_command(cmd)


def get_tf_outputs(dir_path, impersonate_sa=None):
    if not os.path.exists(dir_path):
        return {}, None
    stdout, err = run_command(
        ["terraform", f"-chdir={dir_path}", "output", "-json"],
        impersonate_sa=impersonate_sa,
    )
    if err or not stdout:
        return {}, err
    try:
        outputs = json.loads(stdout)
        return {
            k: (v.get("value") if isinstance(v, dict) else None)
            for k, v in outputs.items()
        }, None
    except Exception as e:
        return {}, f"Failed to parse TF outputs in {dir_path}: {e}"


def check_project_vms(project, clean, impersonate_sa):
    stdout, err = run_command(
        [
            "gcloud",
            "compute",
            "instances",
            "list",
            "--project",
            project,
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if _is_not_found_or_disabled(err, allow_service_disabled=True):
            return True, []
        return False, [f"  [-] [{project}] Failed to query Compute instances: {err}"]
    if not stdout:
        return True, []
    try:
        vms = json.loads(stdout)
    except Exception as e:
        return False, [f"  [-] [{project}] Failed to parse Compute instances JSON: {e}"]

    if not vms:
        return True, []

    msgs = []
    ok = True
    for vm in vms:
        name = vm.get("name", "unknown")
        zone = vm.get("zone", "").split("/")[-1]
        if clean and name and zone:
            _, del_err = run_command(
                [
                    "gcloud",
                    "compute",
                    "instances",
                    "delete",
                    name,
                    "--zone",
                    zone,
                    "--project",
                    project,
                    "--quiet",
                ],
                impersonate_sa=impersonate_sa,
            )
            if del_err:
                msgs.append(
                    f"  [-] [{project}] Failed to delete VM {name} ({zone}): {del_err}"
                )
                ok = False
            else:
                msgs.append(f"  [+] [{project}] Deleted blocker VM: {name} ({zone})")
        else:
            msgs.append(
                f"  [!] [{project}] Active VM '{name}' in zone '{zone}' will block subnet/project teardown"
            )
            ok = False
    return ok, msgs


def check_project_firewalls(project, clean, impersonate_sa):
    # Note: 02-networking exclusively provisions Hierarchical and Global Network Firewall Policies
    # (zero classic google_compute_firewall resources), so any classic firewall rule in a lab VPC
    # project is an unmanaged/manual rule that will block VPC deletion.
    stdout, err = run_command(
        [
            "gcloud",
            "compute",
            "firewall-rules",
            "list",
            "--project",
            project,
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if _is_not_found_or_disabled(err, allow_service_disabled=True):
            return True, []
        return False, [
            f"  [-] [{project}] Failed to query classic firewall rules: {err}"
        ]
    if not stdout:
        return True, []
    try:
        rules = json.loads(stdout)
    except Exception as e:
        return False, [f"  [-] [{project}] Failed to parse firewall rules JSON: {e}"]

    if not rules:
        return True, []

    msgs = []
    ok = True
    for rule in rules:
        name = rule.get("name", "unknown")
        network = rule.get("network", "").split("/")[-1]
        if clean and name:
            _, del_err = run_command(
                [
                    "gcloud",
                    "compute",
                    "firewall-rules",
                    "delete",
                    name,
                    "--project",
                    project,
                    "--quiet",
                ],
                impersonate_sa=impersonate_sa,
            )
            if del_err:
                msgs.append(
                    f"  [-] [{project}] Failed to delete firewall rule {name} ({network}): {del_err}"
                )
                ok = False
            else:
                msgs.append(
                    f"  [+] [{project}] Deleted manual firewall rule: {name} (VPC: {network})"
                )
        else:
            msgs.append(
                f"  [!] [{project}] Manual firewall rule '{name}' on VPC '{network}' will block VPC deletion"
            )
            ok = False
    return ok, msgs


def check_project_forwarding_rules(project, clean, impersonate_sa):
    stdout, err = run_command(
        [
            "gcloud",
            "compute",
            "forwarding-rules",
            "list",
            "--project",
            project,
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if _is_not_found_or_disabled(err, allow_service_disabled=True):
            return True, []
        return False, [f"  [-] [{project}] Failed to query forwarding rules: {err}"]
    if not stdout:
        return True, []
    try:
        fwd_rules = json.loads(stdout)
    except Exception as e:
        return False, [f"  [-] [{project}] Failed to parse forwarding rules JSON: {e}"]

    if not fwd_rules:
        return True, []

    msgs = []
    ok = True
    for fwd in fwd_rules:
        name = fwd.get("name", "unknown")
        region = fwd.get("region", "").split("/")[-1]
        if clean and name:
            del_cmd = [
                "gcloud",
                "compute",
                "forwarding-rules",
                "delete",
                name,
                "--project",
                project,
                "--quiet",
            ]
            if region:
                del_cmd.extend(["--region", region])
            else:
                del_cmd.append("--global")
            _, del_err = run_command(del_cmd, impersonate_sa=impersonate_sa)
            if del_err:
                msgs.append(
                    f"  [-] [{project}] Failed to delete forwarding rule {name}: {del_err}"
                )
                ok = False
            else:
                msgs.append(
                    f"  [+] [{project}] Deleted forwarding rule: {name} ({region or 'global'})"
                )
        else:
            msgs.append(
                f"  [!] [{project}] Forwarding rule / PSC endpoint '{name}' ({region or 'global'}) will block subnet/VPC deletion"
            )
            ok = False
    return ok, msgs


def check_project_peerings_and_dns(project, managed_peerings, impersonate_sa):
    msgs = []
    ok = True

    # 1. Check VPC Peerings (including PSA servicenetworking peerings)
    stdout, err = run_command(
        [
            "gcloud",
            "compute",
            "networks",
            "peerings",
            "list",
            "--project",
            project,
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if not _is_not_found_or_disabled(err, allow_service_disabled=True):
            msgs.append(f"  [-] [{project}] Failed to query VPC peerings: {err}")
            ok = False
    elif stdout:
        try:
            networks = json.loads(stdout)
            for net in networks:
                net_name = net.get("name", "unknown")
                for peer in net.get("peerings", []):
                    peer_name = peer.get("name", "unknown")
                    if peer_name in managed_peerings:
                        continue
                    state = peer.get("state", "UNKNOWN")
                    if state == "ACTIVE":
                        msgs.append(
                            f"  [!] [{project}] Unmanaged active VPC peering '{peer_name}' on VPC '{net_name}' will block VPC deletion"
                        )
                        ok = False
        except Exception as e:
            msgs.append(f"  [-] [{project}] Failed to parse VPC peerings JSON: {e}")
            ok = False

    # 2. Check Cloud DNS Private Managed Zones (allow SERVICE_DISABLED when DNS API was never enabled)
    dns_out, dns_err = run_command(
        [
            "gcloud",
            "dns",
            "managed-zones",
            "list",
            "--project",
            project,
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if dns_err:
        if not _is_not_found_or_disabled(dns_err, allow_service_disabled=True):
            msgs.append(f"  [-] [{project}] Failed to query Cloud DNS zones: {dns_err}")
            ok = False
    elif dns_out:
        try:
            zones = json.loads(dns_out)
            for z in zones:
                if z.get("visibility") == "private" and z.get(
                    "privateVisibilityConfig", {}
                ).get("networks"):
                    z_name = z.get("name", "unknown")
                    msgs.append(
                        f"  [!] [{project}] Private Cloud DNS zone '{z_name}' bound to VPC will block VPC deletion"
                    )
                    ok = False
        except Exception as e:
            msgs.append(f"  [-] [{project}] Failed to parse Cloud DNS zones JSON: {e}")
            ok = False

    return ok, msgs


def _rest_request(url, token, method="GET"):
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read().decode("utf-8")
            return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return None, f"HTTP {e.code}: {body}"
    except Exception as e:
        return None, str(e)


def check_project_liens(project, clean, access_token, is_svpc_host=False):
    # Query Cloud Resource Manager v1 Liens API directly so gcloud alpha is not required.
    if not access_token:
        return False, [
            f"  [-] [{project}] Cannot check project liens: missing access token."
        ]

    parent_param = urllib.parse.quote(f"projects/{project}", safe="/")
    list_url = (
        f"https://cloudresourcemanager.googleapis.com/v1/liens?parent={parent_param}"
    )
    data, err = _rest_request(list_url, access_token, method="GET")
    if err:
        if _is_not_found_or_disabled(err):
            return True, []
        return False, [f"  [-] [{project}] Failed to query project liens: {err}"]

    liens = (data or {}).get("liens", [])
    if not liens:
        return True, []

    msgs = []
    ok = True
    for lien in liens:
        raw_name = lien.get("name", "")
        short_name = raw_name.split("/")[-1]
        reason = lien.get("reason", "no reason specified")
        # Ignore the standard GCP Shared VPC host project lien on Terraform-managed
        # host projects (Terraform removes it automatically when disabling Shared VPC host).
        if is_svpc_host and "shared vpc host project" in reason.lower():
            continue
        if clean and short_name:
            lien_path = raw_name if raw_name.startswith("liens/") else f"liens/{short_name}"
            del_url = f"https://cloudresourcemanager.googleapis.com/v1/{lien_path}"
            _, del_err = _rest_request(del_url, access_token, method="DELETE")
            if del_err:
                msgs.append(
                    f"  [-] [{project}] Failed to delete project lien {short_name}: {del_err}"
                )
                ok = False
            else:
                msgs.append(
                    f"  [+] [{project}] Deleted project lien: {short_name} ({reason})"
                )
        else:
            msgs.append(
                f"  [!] [{project}] Project lien '{short_name}' ({reason}) will block project deletion"
            )
            ok = False
    return ok, msgs


def check_resource_tag_bindings(parent_full_name, managed_tag_values, clean, impersonate_sa):
    if not managed_tag_values:
        return True, []

    stdout, err = run_command(
        [
            "gcloud",
            "resource-manager",
            "tags",
            "bindings",
            "list",
            f"--parent={parent_full_name}",
            "--format=json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if _is_not_found_or_disabled(err, allow_service_disabled=True):
            return True, []
        return False, [
            f"  [-] [{parent_full_name}] Failed to query Secure Tag bindings: {err}"
        ]
    if not stdout:
        return True, []

    try:
        bindings = json.loads(stdout)
    except Exception as e:
        return False, [
            f"  [-] [{parent_full_name}] Failed to parse Secure Tag bindings JSON: {e}"
        ]

    msgs = []
    ok = True
    for b in bindings:
        tag_val = b.get("tagValue", "")
        if tag_val not in managed_tag_values:
            continue
        if clean:
            _, del_err = run_command(
                [
                    "gcloud",
                    "resource-manager",
                    "tags",
                    "bindings",
                    "delete",
                    f"--parent={parent_full_name}",
                    f"--tag-value={tag_val}",
                    "--quiet",
                ],
                impersonate_sa=impersonate_sa,
            )
            if del_err:
                msgs.append(
                    f"  [-] [{parent_full_name}] Failed to delete Secure Tag binding '{tag_val}': {del_err}"
                )
                ok = False
            else:
                msgs.append(
                    f"  [+] [{parent_full_name}] Deleted Secure Tag binding: {tag_val}"
                )
        else:
            msgs.append(
                f"  [!] [{parent_full_name}] Active Secure Tag binding '{tag_val}' will block TagValue deletion"
            )
            ok = False
    return ok, msgs


def check_extra_svpc_attachments(
    host_project, expected_service_projects, stage, impersonate_sa
):
    stdout, err = run_command(
        [
            "gcloud",
            "compute",
            "shared-vpc",
            "associated-projects",
            "list",
            host_project,
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if _is_not_found_or_disabled(err, allow_service_disabled=True):
            return True, []
        return False, [
            f"  [-] [{host_project}] Failed to query Shared VPC associated projects: {err}"
        ]
    if not stdout:
        return True, []
    try:
        attached = json.loads(stdout)
    except Exception as e:
        return False, [
            f"  [-] [{host_project}] Failed to parse Shared VPC associated projects JSON: {e}"
        ]

    msgs = []
    ok = True
    for item in attached:
        svc_proj = item.get("id")
        if not svc_proj:
            continue
        if stage in ("core", "foundation"):
            msgs.append(
                f"  [!] [{host_project}] Shared VPC service project '{svc_proj}' is still attached (destroy 02-networking before 01-foundation)"
            )
            ok = False
        elif svc_proj not in expected_service_projects:
            msgs.append(
                f"  [!] [{host_project}] Unmanaged Shared VPC service project '{svc_proj}' is attached and will block host project teardown"
            )
            ok = False
    return ok, msgs


def check_unmanaged_projects_in_folder(
    folder_id, managed_projects, stage, impersonate_sa
):
    clean_folder = str(folder_id).replace("folders/", "").strip()
    if not clean_folder:
        return True, []
    stdout, err = run_command(
        [
            "gcloud",
            "projects",
            "list",
            "--filter",
            f"parent.id={clean_folder} AND lifecycleState=ACTIVE",
            "--format",
            "json",
        ],
        impersonate_sa=impersonate_sa,
    )
    if err:
        if _is_not_found_or_disabled(err):
            return True, []
        return False, [
            f"  [-] [folders/{clean_folder}] Failed to list projects in folder: {err}"
        ]
    if not stdout:
        return True, []
    try:
        projects = json.loads(stdout)
    except Exception as e:
        return False, [
            f"  [-] [folders/{clean_folder}] Failed to parse projects list JSON: {e}"
        ]

    msgs = []
    ok = True
    for p in projects:
        pid = p.get("projectId")
        if pid and pid not in managed_projects:
            msgs.append(
                f"  [!] [folders/{clean_folder}] Unmanaged ACTIVE project '{pid}' inside lab folder will block folder deletion"
            )
            ok = False
    return ok, msgs


def _vpc_self_link_to_full_resource_name(self_link):
    if not self_link:
        return None
    marker = "/projects/"
    idx = self_link.find(marker)
    if idx != -1:
        return f"//compute.googleapis.com{self_link[idx:]}"
    if self_link.startswith("projects/"):
        return f"//compute.googleapis.com/{self_link}"
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Check (and optionally clean) teardown blockers across network lab VPCs, projects, tags, and folders."
    )
    parser.add_argument(
        "--lab-dir",
        default=".",
        help="Path to the lab directory (containing 01-foundation and 02-networking)",
    )
    parser.add_argument(
        "--impersonate-sa",
        default=os.environ.get("GOOGLE_IMPERSONATE_SERVICE_ACCOUNT")
        or os.environ.get("CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT"),
        help="Service Account email to impersonate for Terraform and gcloud commands",
    )
    parser.add_argument(
        "--stage",
        choices=["all", "networking", "foundation", "base-arch", "core"],
        default="all",
        help="Stage being torn down: 'all' (default), 'networking', or 'foundation'",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Automatically delete safe standalone blockers (VMs, manual firewall rules, forwarding rules, Secure Tag bindings, and project liens)",
    )
    args = parser.parse_args()

    core_dir = os.path.join(args.lab_dir, "01-foundation")
    if not os.path.exists(core_dir):
        core_dir = os.path.join(args.lab_dir, "01-core")
    base_arch_dir = os.path.join(args.lab_dir, "02-networking")
    if not os.path.exists(base_arch_dir):
        base_arch_dir = os.path.join(args.lab_dir, "02-base-arch")

    print("Retrieving Terraform outputs for teardown check...")
    core_outputs, core_err = get_tf_outputs(
        core_dir, impersonate_sa=args.impersonate_sa
    )
    base_outputs, _ = get_tf_outputs(base_arch_dir, impersonate_sa=args.impersonate_sa)

    if not core_outputs:
        print(
            f"Error: Could not read 01-foundation outputs from {core_dir}: {core_err or 'No outputs found'}"
        )
        sys.exit(1)

    access_token, token_err = get_access_token(impersonate_sa=args.impersonate_sa)
    if token_err or not access_token:
        print(f"Error: Could not obtain gcloud access token: {token_err}")
        sys.exit(1)

    on_prem_project = core_outputs.get("on_prem_project_id")
    prod_projects = core_outputs.get("prod_project_ids") or {}
    dev_projects = core_outputs.get("dev_project_ids") or {}

    prod_host = prod_projects.get("prj-p-net-host") or prod_projects.get("host")
    prod_transit = prod_projects.get("prj-p-net-transit") or prod_projects.get(
        "transit"
    )
    dev_host = dev_projects.get("prj-d-net-host") or dev_projects.get("host")
    dev_transit = dev_projects.get("prj-d-net-transit") or dev_projects.get("transit")

    svc_projects_map = (base_outputs or {}).get("prod_service_project_ids") or {}
    svc_projects = (
        set(svc_projects_map.values()) if isinstance(svc_projects_map, dict) else set()
    )

    vpc_peerings_map = (base_outputs or {}).get("vpc_peerings") or {}
    managed_peerings = set()
    if isinstance(vpc_peerings_map, dict):
        for pair in vpc_peerings_map.values():
            if isinstance(pair, dict):
                managed_peerings.update(v for v in pair.values() if v)

    fw_tags_map = (base_outputs or {}).get("firewall_secure_tags") or {}
    managed_tag_values = (
        {v for v in fw_tags_map.values() if isinstance(v, str) and v}
        if isinstance(fw_tags_map, dict)
        else set()
    )

    vpc_self_links_map = (base_outputs or {}).get("vpc_self_links") or {}
    vpc_full_names = []
    if isinstance(vpc_self_links_map, dict):
        for sl in vpc_self_links_map.values():
            full_name = _vpc_self_link_to_full_resource_name(sl)
            if full_name:
                vpc_full_names.append(full_name)

    core_project_set = {
        p for p in [on_prem_project, prod_host, prod_transit, dev_host, dev_transit] if p
    }
    vpc_projects = [p for p in [on_prem_project, prod_host, prod_transit] if p]
    all_managed_projects = sorted(core_project_set | svc_projects)

    # Collect all 8 folder IDs from 01-foundation outputs
    folder_ids = []
    if core_outputs.get("base_folder_id"):
        folder_ids.append(core_outputs["base_folder_id"])
    for fmap_key in (
        "level2_folder_ids",
        "prod_level3_folder_ids",
        "dev_level3_folder_ids",
    ):
        fmap = core_outputs.get(fmap_key) or {}
        if isinstance(fmap, dict):
            folder_ids.extend(fmap.values())

    all_ok = True
    all_msgs = []

    with ThreadPoolExecutor(max_workers=16) as executor:
        futures = []

        # 1. Check VMs, Forwarding Rules, and Liens across active projects
        svpc_hosts = {p for p in (prod_host, dev_host) if p}
        target_projects = (
            sorted(svc_projects | set(vpc_projects))
            if args.stage in ("networking", "base-arch")
            else all_managed_projects
        )
        for proj in target_projects:
            futures.append(
                executor.submit(
                    check_project_vms, proj, args.clean, args.impersonate_sa
                )
            )
            futures.append(
                executor.submit(
                    check_project_forwarding_rules,
                    proj,
                    args.clean,
                    args.impersonate_sa,
                )
            )
            futures.append(
                executor.submit(
                    check_project_liens,
                    proj,
                    args.clean,
                    access_token,
                    proj in svpc_hosts,
                )
            )

        # 2. Check Manual Firewall Rules, VPC Peerings, Private DNS Zones, and Secure Tag Bindings
        if args.stage in ("all", "networking", "base-arch"):
            for proj in vpc_projects:
                futures.append(
                    executor.submit(
                        check_project_firewalls,
                        proj,
                        args.clean,
                        args.impersonate_sa,
                    )
                )
                futures.append(
                    executor.submit(
                        check_project_peerings_and_dns,
                        proj,
                        managed_peerings,
                        args.impersonate_sa,
                    )
                )

            if managed_tag_values:
                tag_parents = []
                for fid in folder_ids:
                    clean_fid = str(fid).replace("folders/", "").strip()
                    if clean_fid:
                        tag_parents.append(
                            f"//cloudresourcemanager.googleapis.com/folders/{clean_fid}"
                        )
                for proj in all_managed_projects:
                    tag_parents.append(
                        f"//cloudresourcemanager.googleapis.com/projects/{proj}"
                    )
                tag_parents.extend(vpc_full_names)

                for parent_name in tag_parents:
                    futures.append(
                        executor.submit(
                            check_resource_tag_bindings,
                            parent_name,
                            managed_tag_values,
                            args.clean,
                            args.impersonate_sa,
                        )
                    )

        # 3. Check Shared VPC Service Project Attachments on Host Projects
        for host_proj in [p for p in (prod_host, dev_host) if p]:
            futures.append(
                executor.submit(
                    check_extra_svpc_attachments,
                    host_proj,
                    svc_projects,
                    args.stage,
                    args.impersonate_sa,
                )
            )

        # 4. Check for Unmanaged Active Projects inside Lab Folders
        if args.stage in ("all", "foundation", "core"):
            expected_in_folders = (
                core_project_set
                if args.stage in ("foundation", "core")
                else set(all_managed_projects)
            )
            for fid in folder_ids:
                futures.append(
                    executor.submit(
                        check_unmanaged_projects_in_folder,
                        fid,
                        expected_in_folders,
                        args.stage,
                        args.impersonate_sa,
                    )
                )

        for future in futures:
            ok, msgs = future.result()
            if not ok:
                all_ok = False
            all_msgs.extend(msgs)

    print("\nPre-Teardown Blocker Report:")
    print("============================")
    if all_msgs:
        for m in all_msgs:
            print(m)
    else:
        print("  [+] No teardown blockers detected across VPCs, tags, projects, or folders.")
    print("============================")

    if all_ok:
        print("PRE-TEARDOWN CHECK PASSED: Safe to proceed with terraform destroy.")
        sys.exit(0)
    else:
        print(
            "PRE-TEARDOWN CHECK FOUND BLOCKERS OR ERRORS: Run with --clean to auto-delete VMs/firewalls/forwarding-rules/tag-bindings/liens, or resolve remaining issues manually before terraform destroy."
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
