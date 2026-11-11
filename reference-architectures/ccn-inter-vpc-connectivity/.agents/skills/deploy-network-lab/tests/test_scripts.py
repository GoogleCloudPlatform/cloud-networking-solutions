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

import importlib.util
import io
import json
import os
import tempfile
import unittest
from unittest import mock

SCRIPTS_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "scripts")
)


def _load_script(module_name, filename):
    spec = importlib.util.spec_from_file_location(
        module_name, os.path.join(SCRIPTS_DIR, filename)
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_prereqs = _load_script("check_prereqs", "check_prereqs.py")
check_teardown = _load_script("check_teardown", "check_teardown.py")
verify_deployment = _load_script("verify_deployment", "verify_deployment.py")
find_vars = _load_script("find_vars", "find_vars.py")
summarize_plan = _load_script("summarize_plan", "summarize_plan.py")


class CheckPrereqsTests(unittest.TestCase):

    def test_required_org_roles_include_firewall_and_tag_roles(self):
        ncc_roles = [r[0] for r in check_prereqs.get_required_org_roles("ncc")]
        peer_roles = [
            r[0] for r in check_prereqs.get_required_org_roles("vpc-peering")
        ]

        for expected in (
            "roles/compute.orgSecurityPolicyAdmin",
            "roles/compute.orgSecurityResourceAdmin",
            "roles/resourcemanager.tagAdmin",
            "roles/resourcemanager.tagUser",
        ):
            self.assertIn(expected, ncc_roles)
            self.assertIn(expected, peer_roles)

        self.assertIn("roles/networkconnectivity.admin", ncc_roles)
        self.assertNotIn("roles/networkconnectivity.admin", peer_roles)

    def test_billing_impersonation_does_not_fallback_to_human_user(self):
        calls = []

        def fake_run(cmd):
            calls.append(cmd)
            return None, "PERMISSION_DENIED: caller does not have permission"

        with mock.patch.object(check_prereqs, "run_command", side_effect=fake_run):
            ok, msg, remedies = check_prereqs.check_billing_account(
                "012345-6789AB-CDEF01",
                "tf-runner@proj.iam.gserviceaccount.com",
                "serviceAccount",
                "tf-runner@proj.iam.gserviceaccount.com",
            )

        self.assertIs(ok, False)
        self.assertEqual(len(calls), 1)
        self.assertIn(
            "--impersonate-service-account=tf-runner@proj.iam.gserviceaccount.com",
            calls[0],
        )
        self.assertTrue(any("roles/billing.user" in r for r in remedies))
        self.assertIn("cannot access billing account", msg)

    def test_impersonation_checks_both_cli_and_adc(self):
        with mock.patch.object(
            check_prereqs, "run_command", return_value=("cli-token", None)
        ), mock.patch.object(
            check_prereqs,
            "_generate_impersonated_token_via_adc",
            return_value=(False, "HTTP 403 via ADC"),
        ):
            ok, msg = check_prereqs.check_impersonation(
                "tf-runner@proj.iam.gserviceaccount.com"
            )

        self.assertFalse(ok)
        self.assertIn("Application Default Credentials (ADC) failed", msg)

    def test_prefix_validation_and_collision_detection(self):
        ok, msg, _ = check_prereqs.check_prefix_collisions("too-long-prefix", "12345")
        self.assertIs(ok, False)
        self.assertIn("Invalid prefix", msg)

        with mock.patch.object(
            check_prereqs,
            "run_command",
            return_value=(json.dumps([{"name": "folders/999"}]), None),
        ):
            ok2, msg2, _ = check_prereqs.check_prefix_collisions("ncc", "12345")
        self.assertIsNone(ok2)
        self.assertIn("already exists", msg2)


class CheckTeardownTests(unittest.TestCase):

    def test_vm_check_surfaces_permission_errors_instead_of_false_pass(self):
        with mock.patch.object(
            check_teardown,
            "run_command",
            return_value=(None, "ERROR: (gcloud.compute.instances.list) PERMISSION_DENIED"),
        ):
            ok, msgs = check_teardown.check_project_vms("prj-test", False, None)

        self.assertFalse(ok)
        self.assertTrue(any("Failed to query Compute instances" in m for m in msgs))

    def test_dns_service_disabled_is_treated_as_no_zones(self):
        def fake_run(cmd, cwd=None, impersonate_sa=None):
            if "peerings" in cmd:
                return "[]", None
            return None, "API [dns.googleapis.com] has not been used in project prj-test"

        with mock.patch.object(check_teardown, "run_command", side_effect=fake_run):
            ok, msgs = check_teardown.check_project_peerings_and_dns(
                "prj-test", set(), None
            )

        self.assertTrue(ok)
        self.assertEqual(msgs, [])

    def test_project_liens_uses_rest_and_ignores_svpc_host_lien(self):
        liens_payload = {
            "liens": [
                {
                    "name": "liens/p123-svpc",
                    "reason": "Shared VPC host project cannot be deleted",
                },
                {
                    "name": "liens/p123-custom",
                    "reason": "Manual production lock",
                },
            ]
        }
        with mock.patch.object(
            check_teardown, "_rest_request", return_value=(liens_payload, None)
        ):
            ok, msgs = check_teardown.check_project_liens(
                "prj-host", False, "tok", is_svpc_host=True
            )

        self.assertFalse(ok)
        self.assertEqual(len(msgs), 1)
        self.assertIn("p123-custom", msgs[0])

    def test_secure_tag_binding_detect_and_clean(self):
        bindings_json = json.dumps(
            [
                {"tagValue": "tagValues/111"},
                {"tagValue": "tagValues/999-unrelated"},
            ]
        )
        calls = []

        def fake_run(cmd, cwd=None, impersonate_sa=None):
            calls.append(cmd)
            if "list" in cmd:
                return bindings_json, None
            return "", None

        with mock.patch.object(check_teardown, "run_command", side_effect=fake_run):
            ok_detect, msgs_detect = check_teardown.check_resource_tag_bindings(
                "//cloudresourcemanager.googleapis.com/projects/prj-1",
                {"tagValues/111"},
                clean=False,
                impersonate_sa=None,
            )
            ok_clean, msgs_clean = check_teardown.check_resource_tag_bindings(
                "//cloudresourcemanager.googleapis.com/projects/prj-1",
                {"tagValues/111"},
                clean=True,
                impersonate_sa=None,
            )

        self.assertFalse(ok_detect)
        self.assertTrue(any("tagValues/111" in m for m in msgs_detect))
        self.assertTrue(ok_clean)
        self.assertTrue(any("Deleted Secure Tag binding" in m for m in msgs_clean))


class VerifyDeploymentAndHelpersTests(unittest.TestCase):

    def test_verify_ncc_spokes_checks_vpc_and_hybrid_spokes(self):
        hub_uri = "projects/prj-transit/locations/global/hubs/ncc-hub-prod"
        spokes = [
            {
                "name": "projects/prj-transit/locations/global/spokes/spoke-p-vpc-transit",
                "hub": hub_uri,
                "state": "ACTIVE",
            },
            *[
                {
                    "name": f"projects/prj-transit/locations/us-east4/spokes/spoke-p-hybrid-vpn-{i}",
                    "hub": hub_uri,
                    "state": "ACTIVE",
                    "linkedVpnTunnels": {"uris": ["t1"]},
                }
                for i in range(4)
            ],
        ]
        with mock.patch.object(
            verify_deployment, "run_command", return_value=(json.dumps(spokes), None)
        ):
            ok = verify_deployment.verify_ncc_spokes(
                "prj-transit",
                "prj-transit",
                "ncc-hub-prod",
                expected_vpc_spokes=["spoke-p-vpc-transit"],
                expected_hybrid_spoke_count=4,
                hub_uri=hub_uri,
            )
        self.assertTrue(ok)

    def test_verify_firewall_policies_checks_hierarchical_and_network_policies(self):
        for hp_payload in (
            [
                {
                    "displayName": "hfwp-ncc-network-lab",
                    "shortName": "hfwp-ncc-network-lab",
                    "associations": [{"attachmentTarget": "folders/12345"}],
                }
            ],
            {
                "shortName": "hfwp-ncc-network-lab",
                "associations": [{"attachmentTarget": "folders/12345"}],
            },
        ):
            def fake_run(cmd, cwd=None, impersonate_sa=None, _payload=hp_payload):
                if "firewall-policies" in cmd:
                    return json.dumps(_payload), None
                return (
                    json.dumps(
                        [
                            {
                                "name": "gfwp-vpc-on-prem",
                                "associations": [{"name": "assoc-vpc-on-prem"}],
                            }
                        ]
                    ),
                    None,
                )

            with mock.patch.object(
                verify_deployment, "run_command", side_effect=fake_run
            ):
                ok = verify_deployment.verify_firewall_policies(
                    base_folder_id="folders/12345",
                    hierarchical_policy_id="locations/global/firewallPolicies/98765",
                    network_firewall_policies={"on_prem": "gfwp-vpc-on-prem"},
                    on_prem_project="prj-onprem",
                    transit_project="prj-transit",
                    host_project="prj-host",
                )
            self.assertTrue(ok)

        with mock.patch.object(
            verify_deployment, "run_command", return_value=("[]", None)
        ):
            ok_empty = verify_deployment.verify_firewall_policies(
                base_folder_id="folders/12345",
                hierarchical_policy_id="locations/global/firewallPolicies/98765",
                network_firewall_policies={},
                on_prem_project="prj-onprem",
                transit_project="prj-transit",
                host_project="prj-host",
            )
        self.assertFalse(ok_empty)

    def test_find_vars_and_summarize_plan(self):
        hcl = '''
        # variable "commented_out" {}
        variable "org_id" {
          type = string
        }
        variable "prefix" {
          type    = string
          default = "ncc"
        }
        '''
        with tempfile.NamedTemporaryFile("w", suffix=".tf", delete=False) as tf_file:
            tf_file.write(hcl)
            tf_path = tf_file.name
        try:
            req = find_vars.find_variables_without_defaults(tf_path)
            self.assertEqual(req, ["org_id"])
        finally:
            os.remove(tf_path)

        plan = {
            "resource_changes": [
                {"type": "google_project", "address": "google_project.p1", "change": {"actions": ["create"]}},
                {"type": "google_compute_subnetwork", "address": "google_compute_subnetwork.s1", "change": {"actions": ["delete", "create"]}},
            ]
        }
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as pf:
            json.dump(plan, pf)
            plan_path = pf.name
        try:
            buf = io.StringIO()
            with mock.patch("sys.stdout", buf):
                summarize_plan.summarize_plan(plan_path)
            out = buf.getvalue()
            self.assertIn("Create: 1", out)
            self.assertIn("Replace: 1", out)
            self.assertIn("[REPLACE] google_compute_subnetwork.s1", out)
        finally:
            os.remove(plan_path)


if __name__ == "__main__":
    unittest.main()
