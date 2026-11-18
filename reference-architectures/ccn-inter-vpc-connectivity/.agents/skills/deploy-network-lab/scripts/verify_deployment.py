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
import time


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


def get_tf_outputs(dir_path, impersonate_sa=None):
    stdout, err = run_command(
        ["terraform", f"-chdir={dir_path}", "output", "-json"],
        impersonate_sa=impersonate_sa,
    )
    if err:
        return None, f"Failed to get TF outputs in {dir_path}: {err}"
    try:
        outputs = json.loads(stdout)
        return {
            k: (v.get("value") if isinstance(v, dict) else None)
            for k, v in outputs.items()
        }, None
    except Exception as e:
        return None, f"Failed to parse TF outputs: {e}"


def _check_project_tunnels(project, expected_count, impersonate_sa):
    cmd = [
        "gcloud",
        "compute",
        "vpn-tunnels",
        "list",
        "--project",
        project,
        "--format",
        "json",
    ]
    stdout, err = run_command(cmd, impersonate_sa=impersonate_sa)
    if err:
        return False, [f"  [-] Failed to list VPN tunnels in project {project}: {err}"]
    try:
        tunnels = json.loads(stdout)
    except Exception as e:
        return False, [f"  [-] Failed to parse VPN tunnels list for {project}: {e}"]

    msgs = []
    project_ok = True
    if len(tunnels) < expected_count:
        msgs.append(
            f"  [-] Found {len(tunnels)} VPN tunnel(s) in {project} (Expected at least {expected_count})"
        )
        project_ok = False

    for t in sorted(tunnels, key=lambda x: (x.get("region", ""), x.get("name", ""))):
        name = t.get("name", "unknown")
        region = t.get("region", "").split("/")[-1] or "unknown-region"
        status = t.get("status")
        if status == "ESTABLISHED":
            msgs.append(f"  [+] Tunnel {name} ({region}): {status}")
        elif status == "FIRST_HANDSHAKE_RECEIVED":
            msgs.append(
                f"  [!] Tunnel {name} ({region}): {status} (IKE negotiating - expected ESTABLISHED)"
            )
            project_ok = False
        else:
            msgs.append(
                f"  [-] Tunnel {name} ({region}): {status} (Expected ESTABLISHED)"
            )
            project_ok = False
    return project_ok, msgs


def verify_all_vpn_tunnels(project_tunnel_expectations, impersonate_sa=None):
    results = {}
    with ThreadPoolExecutor(
        max_workers=len(project_tunnel_expectations) or 1
    ) as executor:
        future_map = {
            executor.submit(
                _check_project_tunnels, proj, exp_count, impersonate_sa
            ): proj
            for proj, exp_count in project_tunnel_expectations
        }
        for future, proj in future_map.items():
            results[proj] = future.result()

    all_ok = True
    for proj, exp_count in project_tunnel_expectations:
        print(f"\nChecking VPN Tunnels in project {proj} (expected: {exp_count})...")
        ok, msgs = results[proj]
        for m in msgs:
            print(m)
        if not ok:
            all_ok = False
    return all_ok


def _list_vpn_routers_in_project(project, expected_count, impersonate_sa):
    cmd = [
        "gcloud",
        "compute",
        "routers",
        "list",
        "--project",
        project,
        "--filter",
        "name~^router-vpn-",
        "--format",
        "json",
    ]
    stdout, err = run_command(cmd, impersonate_sa=impersonate_sa)
    if err:
        return False, [], f"  [-] Failed to list VPN routers in project {project}: {err}"
    try:
        routers = json.loads(stdout)
    except Exception as e:
        return (
            False,
            [],
            f"  [-] Failed to parse routers list in project {project}: {e}",
        )

    discovered = []
    for r in sorted(routers, key=lambda x: (x.get("region", ""), x.get("name", ""))):
        name = r.get("name")
        region = r.get("region", "").split("/")[-1]
        if name and region:
            discovered.append((project, region, name))

    if len(discovered) < expected_count:
        return (
            False,
            discovered,
            f"  [-] Found {len(discovered)} VPN router(s) in {project} (Expected at least {expected_count})",
        )
    return True, discovered, None


def _check_single_router(project, region, router, impersonate_sa):
    cmd = [
        "gcloud",
        "compute",
        "routers",
        "get-status",
        router,
        "--region",
        region,
        "--project",
        project,
        "--format",
        "json",
    ]
    stdout, err = run_command(cmd, impersonate_sa=impersonate_sa)
    if err:
        return False, [
            f"  [-] Failed to get status for router {router} ({region}): {err}"
        ]
    try:
        data = json.loads(stdout)
        result = data.get("result", data)
        peers = result.get("bgpPeerStatus", [])
        if not peers:
            return False, [
                f"  [-] Router {router} ({region}): No BGP peers configured or status not available."
            ]

        router_ok = True
        msgs = []
        for peer in peers:
            peer_name = peer.get("name")
            peer_status = peer.get("state")
            learned_routes = peer.get("numLearnedRoutes", 0)
            if peer_status == "Established" and learned_routes > 0:
                msgs.append(
                    f"  [+] Router {router} ({region}) -> Peer {peer_name}: {peer_status} (learned routes: {learned_routes})"
                )
            elif peer_status == "Established":
                msgs.append(
                    f"  [!] Router {router} ({region}) -> Peer {peer_name}: {peer_status} (learned routes: 0 - waiting for BGP route exchange)"
                )
                router_ok = False
            else:
                msgs.append(
                    f"  [-] Router {router} ({region}) -> Peer {peer_name}: {peer_status} (Expected Established)"
                )
                router_ok = False
        return router_ok, msgs
    except Exception as e:
        return False, [
            f"  [-] Failed to parse output for router {router} ({region}): {e}"
        ]


def verify_all_routers(project_router_expectations, impersonate_sa=None):
    all_ok = True
    all_routers = []
    list_errors = {}

    with ThreadPoolExecutor(
        max_workers=len(project_router_expectations) or 1
    ) as executor:
        future_map = {
            executor.submit(
                _list_vpn_routers_in_project, proj, exp_count, impersonate_sa
            ): (proj, exp_count)
            for proj, exp_count in project_router_expectations
        }
        for future, (proj, _) in future_map.items():
            ok, discovered, err_msg = future.result()
            if not ok:
                all_ok = False
            list_errors[proj] = err_msg
            all_routers.extend(discovered)

    status_results = {}
    if all_routers:
        with ThreadPoolExecutor(max_workers=len(all_routers) or 1) as executor:
            future_map = {
                executor.submit(
                    _check_single_router, proj, reg, rtr, impersonate_sa
                ): (proj, reg, rtr)
                for proj, reg, rtr in all_routers
            }
            for future, key in future_map.items():
                status_results[key] = future.result()

    for proj, exp_count in project_router_expectations:
        print(
            f"\nChecking BGP sessions on VPN Routers in project {proj} (expected routers: {exp_count})..."
        )
        if list_errors.get(proj):
            print(list_errors[proj])
        proj_routers = [item for item in all_routers if item[0] == proj]
        for proj_id, reg, rtr in proj_routers:
            ok, msgs = status_results[(proj_id, reg, rtr)]
            for m in msgs:
                print(m)
            if not ok:
                all_ok = False
    return all_ok


def get_ncc_hub_uri(hub_project, hub_name, impersonate_sa=None):
    hub_cmd = [
        "gcloud",
        "network-connectivity",
        "hubs",
        "describe",
        hub_name,
        "--project",
        hub_project,
        "--format",
        "json",
    ]
    stdout, err = run_command(hub_cmd, impersonate_sa=impersonate_sa)
    if err:
        print(f"  [-] Failed to describe hub {hub_name} in project {hub_project}: {err}")
        return None
    try:
        hub_data = json.loads(stdout)
        return hub_data.get("name")
    except Exception as e:
        print(f"  [-] Failed to parse hub description: {e}")
        return None


def verify_ncc_spokes(
    spoke_project,
    hub_project,
    hub_name,
    expected_vpc_spokes,
    expected_hybrid_spoke_count=0,
    impersonate_sa=None,
    hub_uri=None,
):
    print(
        f"\nChecking NCC Spokes in project {spoke_project} for Hub {hub_name} (in {hub_project})..."
    )
    if not hub_uri:
        hub_uri = get_ncc_hub_uri(
            hub_project, hub_name, impersonate_sa=impersonate_sa
        )
        if not hub_uri:
            return False

    cmd = [
        "gcloud",
        "network-connectivity",
        "spokes",
        "list",
        "--project",
        spoke_project,
        "--format",
        "json",
    ]
    stdout, err = run_command(cmd, impersonate_sa=impersonate_sa)
    if err:
        print(f"  [-] Failed to list spokes: {err}")
        return False

    try:
        spokes = json.loads(stdout)
        hub_spokes = [s for s in spokes if s.get("hub") == hub_uri]
        spoke_by_name = {
            s.get("name", "").split("/")[-1]: s for s in hub_spokes if s.get("name")
        }

        all_ok = True
        for expected in expected_vpc_spokes:
            if expected not in spoke_by_name:
                print(f"  [-] VPC Spoke {expected}: Not found on hub {hub_name}")
                all_ok = False
                continue

            state = spoke_by_name[expected].get("state")
            if state == "ACTIVE":
                print(f"  [+] VPC Spoke {expected}: {state}")
            else:
                print(f"  [-] VPC Spoke {expected}: {state} (Expected ACTIVE)")
                all_ok = False

        if expected_hybrid_spoke_count > 0:
            hybrid_spokes = sorted(
                [
                    (sname, s)
                    for sname, s in spoke_by_name.items()
                    if s.get("linkedVpnTunnels") or sname.startswith("spoke-p-hybrid-")
                ],
                key=lambda x: x[0],
            )
            if len(hybrid_spokes) < expected_hybrid_spoke_count:
                print(
                    f"  [-] Found {len(hybrid_spokes)} Hybrid VPN spoke(s) in {spoke_project} (Expected at least {expected_hybrid_spoke_count})"
                )
                all_ok = False
            for sname, spoke in hybrid_spokes:
                state = spoke.get("state")
                if state == "ACTIVE":
                    print(f"  [+] Hybrid Spoke {sname}: {state}")
                else:
                    print(f"  [-] Hybrid Spoke {sname}: {state} (Expected ACTIVE)")
                    all_ok = False

        return all_ok
    except Exception as e:
        print(f"  [-] Failed to parse spokes list: {e}")
        return False


def verify_vpc_peerings(
    transit_project, host_project, expected_peerings, impersonate_sa=None
):
    print(f"\nChecking VPC Network Peerings in {transit_project} and {host_project}...")
    all_ok = True

    def _list_peerings(project):
        cmd = [
            "gcloud",
            "compute",
            "networks",
            "peerings",
            "list",
            "--project",
            project,
            "--format",
            "json",
        ]
        stdout, err = run_command(cmd, impersonate_sa=impersonate_sa)
        if err:
            print(f"  [-] Failed to list VPC peerings in {project}: {err}")
            return None
        try:
            networks = json.loads(stdout)
            peerings_map = {}
            for net in networks:
                net_name = net.get("name", "")
                for p in net.get("peerings", []):
                    peerings_map[(net_name, p.get("name", ""))] = p
            return peerings_map
        except Exception as e:
            print(f"  [-] Failed to parse VPC peerings in {project}: {e}")
            return None

    transit_peerings = _list_peerings(transit_project)
    host_peerings = _list_peerings(host_project)
    if transit_peerings is None or host_peerings is None:
        return False

    spoke_vpc_names = {
        "app1": "vpc-p-svpc-app-01",
        "app2": "vpc-p-svpc-app-02",
        "app3": "vpc-p-svpc-app-03",
    }

    for key, pair in sorted(expected_peerings.items()):
        t2s_name = pair.get("transit_to_spoke")
        s2t_name = pair.get("spoke_to_transit")
        spoke_vpc = spoke_vpc_names.get(key, f"vpc-p-svpc-{key}")

        t2s = transit_peerings.get(("vpc-p-transit", t2s_name))
        if not t2s:
            print(f"  [-] Peering {t2s_name} (vpc-p-transit): Not found")
            all_ok = False
        elif t2s.get("state") == "ACTIVE":
            print(
                f"  [+] Peering {t2s_name} (vpc-p-transit -> {spoke_vpc}): {t2s.get('state')}"
            )
        else:
            print(
                f"  [-] Peering {t2s_name} (vpc-p-transit -> {spoke_vpc}): {t2s.get('state')} (Expected ACTIVE)"
            )
            all_ok = False

        s2t = host_peerings.get((spoke_vpc, s2t_name))
        if not s2t:
            print(f"  [-] Peering {s2t_name} ({spoke_vpc}): Not found")
            all_ok = False
        elif s2t.get("state") == "ACTIVE":
            print(
                f"  [+] Peering {s2t_name} ({spoke_vpc} -> vpc-p-transit): {s2t.get('state')}"
            )
        else:
            print(
                f"  [-] Peering {s2t_name} ({spoke_vpc} -> vpc-p-transit): {s2t.get('state')} (Expected ACTIVE)"
            )
            all_ok = False

    return all_ok


def verify_firewall_policies(
    base_folder_id,
    hierarchical_policy_id,
    network_firewall_policies,
    on_prem_project,
    transit_project,
    host_project,
    impersonate_sa=None,
):
    if not hierarchical_policy_id and not network_firewall_policies:
        return True

    print("\nChecking Hierarchical & Global Network Firewall Policies...")
    all_ok = True

    if hierarchical_policy_id:
        clean_policy_id = str(hierarchical_policy_id).split("/")[-1]
        stdout, err = run_command(
            [
                "gcloud",
                "compute",
                "firewall-policies",
                "describe",
                clean_policy_id,
                "--format",
                "json",
            ],
            impersonate_sa=impersonate_sa,
        )
        if err:
            print(
                f"  [-] Failed to describe Hierarchical Firewall Policy {clean_policy_id}: {err}"
            )
            all_ok = False
        else:
            try:
                hp = json.loads(stdout)
                if isinstance(hp, list):
                    hp = hp[0] if hp else {}
                if not isinstance(hp, dict) or not hp:
                    print(
                        f"  [-] Hierarchical Policy ({clean_policy_id}): Unexpected empty or invalid policy payload"
                    )
                    all_ok = False
                else:
                    assocs = hp.get("associations", [])
                    short_name = (
                        hp.get("shortName")
                        or hp.get("displayName")
                        or clean_policy_id
                    )
                    clean_folder = (
                        f"folders/{str(base_folder_id).replace('folders/', '').strip()}"
                        if base_folder_id
                        else None
                    )
                    attached_targets = {a.get("attachmentTarget") for a in assocs}
                    if clean_folder and clean_folder not in attached_targets:
                        print(
                            f"  [-] Hierarchical Policy {short_name} ({clean_policy_id}): Not associated with {clean_folder}"
                        )
                        all_ok = False
                    else:
                        print(
                            f"  [+] Hierarchical Policy {short_name} ({clean_policy_id}): Associated with {clean_folder or 'target folder'}"
                        )
            except Exception as e:
                print(
                    f"  [-] Failed to parse Hierarchical Firewall Policy {clean_policy_id}: {e}"
                )
                all_ok = False

    if isinstance(network_firewall_policies, dict) and network_firewall_policies:
        vpc_key_to_proj = {
            "on_prem": on_prem_project,
            "prod_transit": transit_project,
            "prod_services": host_project,
            "prod_app1": host_project,
            "prod_app2": host_project,
            "prod_app3": host_project,
        }
        projects_to_query = sorted(set(vpc_key_to_proj.values()))
        policies_by_proj = {}

        def _list_net_fw_policies(proj):
            out, e = run_command(
                [
                    "gcloud",
                    "compute",
                    "network-firewall-policies",
                    "list",
                    "--project",
                    proj,
                    "--global",
                    "--format",
                    "json",
                ],
                impersonate_sa=impersonate_sa,
            )
            if e:
                return None, e
            try:
                items = json.loads(out) if out else []
                return {item.get("name"): item for item in items}, None
            except Exception as ex:
                return None, str(ex)

        with ThreadPoolExecutor(max_workers=len(projects_to_query) or 1) as executor:
            fmap = {
                executor.submit(_list_net_fw_policies, p): p for p in projects_to_query
            }
            for fut, p in fmap.items():
                policies_by_proj[p] = fut.result()

        for vpc_key, policy_name in sorted(network_firewall_policies.items()):
            proj = vpc_key_to_proj.get(vpc_key, host_project)
            pmap, perr = policies_by_proj.get(proj, (None, "Not queried"))
            if perr or pmap is None:
                print(
                    f"  [-] Global Network Policy {policy_name} ({proj}): Failed to list policies: {perr}"
                )
                all_ok = False
                continue
            pol = pmap.get(policy_name)
            if not pol:
                print(f"  [-] Global Network Policy {policy_name} ({proj}): Not found")
                all_ok = False
            elif not pol.get("associations"):
                print(
                    f"  [-] Global Network Policy {policy_name} ({proj}): Found, but missing VPC association"
                )
                all_ok = False
            else:
                print(
                    f"  [+] Global Network Policy {policy_name} ({proj}): Associated and active"
                )

    return all_ok


def run_verification_pass(
    on_prem_project,
    transit_project,
    host_project,
    sa,
    check_ncc=True,
    ncc_hub_id=None,
    expected_peerings=None,
    base_folder_id=None,
    hierarchical_policy_id=None,
    network_firewall_policies=None,
):
    success = True

    # 1. Verify all 16 VPN Tunnels via 3 concurrent project-level list calls
    project_tunnel_expectations = [
        (on_prem_project, 4),
        (transit_project, 8),
        (host_project, 4),
    ]
    if not verify_all_vpn_tunnels(project_tunnel_expectations, impersonate_sa=sa):
        success = False

    # 2. Dynamically discover and verify all 6 BGP VPN Routers and learned routes
    project_router_expectations = [
        (on_prem_project, 2),
        (transit_project, 2),
        (host_project, 2),
    ]
    if not verify_all_routers(project_router_expectations, impersonate_sa=sa):
        success = False

    # 3. Verify NCC Spokes or VPC Network Peerings
    if not check_ncc:
        print("\nSkipping NCC Spokes check (enable_ncc is false in 02-networking).")
    else:
        hub_name = (
            str(ncc_hub_id).split("/")[-1]
            if ncc_hub_id and "/" in str(ncc_hub_id)
            else "ncc-hub-prod"
        )
        hub_uri = get_ncc_hub_uri(transit_project, hub_name, impersonate_sa=sa)
        if not hub_uri:
            success = False
        else:
            ncc_ok1 = verify_ncc_spokes(
                transit_project,
                transit_project,
                hub_name,
                expected_vpc_spokes=["spoke-p-vpc-transit"],
                expected_hybrid_spoke_count=4,
                impersonate_sa=sa,
                hub_uri=hub_uri,
            )
            ncc_ok2 = verify_ncc_spokes(
                host_project,
                transit_project,
                hub_name,
                expected_vpc_spokes=[
                    "spoke-p-vpc-app1",
                    "spoke-p-vpc-app2",
                    "spoke-p-vpc-app3",
                ],
                expected_hybrid_spoke_count=0,
                impersonate_sa=sa,
                hub_uri=hub_uri,
            )

            if not (ncc_ok1 and ncc_ok2):
                success = False

    if expected_peerings:
        if not verify_vpc_peerings(
            transit_project, host_project, expected_peerings, impersonate_sa=sa
        ):
            success = False

    # 4. Verify Hierarchical and Global Network Firewall Policies
    if not verify_firewall_policies(
        base_folder_id=base_folder_id,
        hierarchical_policy_id=hierarchical_policy_id,
        network_firewall_policies=network_firewall_policies,
        on_prem_project=on_prem_project,
        transit_project=transit_project,
        host_project=host_project,
        impersonate_sa=sa,
    ):
        success = False

    return success


def main():
    parser = argparse.ArgumentParser(description="Verify network lab deployment status.")
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
        "--retries",
        type=int,
        default=0,
        help="Number of retries if components are still negotiating",
    )
    parser.add_argument(
        "--retry-delay",
        type=int,
        default=30,
        help="Seconds to wait between retries (default: 30)",
    )
    args = parser.parse_args()

    core_dir = os.path.join(args.lab_dir, "01-foundation")
    if not os.path.exists(core_dir):
        core_dir = os.path.join(args.lab_dir, "01-core")
    base_arch_dir = os.path.join(args.lab_dir, "02-networking")
    if not os.path.exists(base_arch_dir):
        base_arch_dir = os.path.join(args.lab_dir, "02-base-arch")

    if not os.path.exists(core_dir) or not os.path.exists(base_arch_dir):
        print(f"Error: Could not find 01-foundation or 02-networking in {args.lab_dir}")
        sys.exit(1)

    if args.impersonate_sa:
        print(f"Using Service Account impersonation: {args.impersonate_sa}")

    print("Retrieving Terraform outputs from 01-foundation and 02-networking...")
    core_outputs, err = get_tf_outputs(core_dir, impersonate_sa=args.impersonate_sa)
    if err or not core_outputs:
        print(
            f"Error reading 01-foundation outputs (ensure 01-foundation has been applied): {err or 'No outputs found'}"
        )
        sys.exit(1)

    base_outputs, base_err = get_tf_outputs(
        base_arch_dir, impersonate_sa=args.impersonate_sa
    )
    if base_err or not base_outputs:
        print(
            f"Error reading 02-networking outputs (ensure 02-networking has been applied): {base_err or 'No outputs found'}"
        )
        sys.exit(1)

    on_prem_project = core_outputs.get("on_prem_project_id")
    prod_projects = core_outputs.get("prod_project_ids") or {}
    transit_project = prod_projects.get("prj-p-net-transit") or prod_projects.get(
        "transit"
    )
    host_project = prod_projects.get("prj-p-net-host") or prod_projects.get("host")

    if not on_prem_project or not transit_project or not host_project:
        print("Error: Missing required project IDs in core outputs.")
        print(
            f"Got: on_prem_project={on_prem_project}, transit_project={transit_project}, host_project={host_project}"
        )
        sys.exit(1)

    ncc_hub_id = base_outputs.get("ncc_hub_id")
    expected_peerings = base_outputs.get("vpc_peerings") or {}
    if "ncc_hub_id" in base_outputs:
        check_ncc = ncc_hub_id is not None
    elif expected_peerings or "vpc_peerings" in base_outputs:
        check_ncc = False
    else:
        check_ncc = True

    max_attempts = max(1, args.retries + 1)
    for attempt in range(1, max_attempts + 1):
        if max_attempts > 1:
            print(f"\n--- Verification Attempt {attempt}/{max_attempts} ---")
        success = run_verification_pass(
            on_prem_project,
            transit_project,
            host_project,
            args.impersonate_sa,
            check_ncc=check_ncc,
            ncc_hub_id=ncc_hub_id,
            expected_peerings=expected_peerings,
            base_folder_id=core_outputs.get("base_folder_id"),
            hierarchical_policy_id=base_outputs.get("hierarchical_firewall_policy_id"),
            network_firewall_policies=base_outputs.get("network_firewall_policies"),
        )
        if success:
            print("\n==================================")
            print(
                "VERIFICATION SUCCESS: All network and security components are ACTIVE and ESTABLISHED."
            )
            sys.exit(0)
        if attempt < max_attempts:
            print(
                f"\nSome components are not ready yet. Retrying in {args.retry_delay}s..."
            )
            time.sleep(args.retry_delay)

    print("\n==================================")
    print("VERIFICATION FAILED: Some components are not in the expected state.")
    sys.exit(1)


if __name__ == "__main__":
    main()
