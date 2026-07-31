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

"""Deploy the mortgage assistant agent to Vertex AI Agent Engine.

Uses the vertexai.agent_engines SDK, with an `installation_scripts` hook that
builds an overlay virtualenv in the container so the agent's dependencies layer
over the base image instead of replacing it (see `_write_overlay_venv_script`).

The agent discovers its MCP tools at runtime by listing `mcpServers` in the
Agent Registry for `--project` / `--region`, so no per-service URL or URI
flags are needed here.

Usage:
    # Create a new agent
    python deploy_agent.py --project=PROJECT_ID --region=us-central1

    # Update an existing agent in-place
    python deploy_agent.py --project=PROJECT_ID --region=us-central1 \
        --update=projects/PROJECT/locations/REGION/reasoningEngines/ENGINE_ID

    # Create with PSC Interface and agent identity
    python deploy_agent.py --project=PROJECT_ID --region=us-central1 \
        --network-attachment=projects/PROJECT/regions/REGION/networkAttachments/NAME \
        --enable-agent-identity

    # Pin the model endpoint to a specific location (default: global)
    python deploy_agent.py --project=PROJECT_ID --region=us-central1 \
        --model-endpoint-location=us-central1

    # Register an existing reasoning engine in Gemini Enterprise only (no redeploy)
    OAUTH_CLIENT_SECRET=... python deploy_agent.py --project=PROJECT_ID \
        --ge-deploy-only=projects/PROJECT/locations/REGION/reasoningEngines/ENGINE_ID \
        --app-id=GE_ENGINE_ID \
        --oauth-client-id=CLIENT_ID
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.request

# Contents of the installation script executed by step 16/29 of the Agent Engine
# build ("Executing user-provided UNIX commands from scripts in
# ./installation_scripts"), before the requirements install in step 19.
#
# DO NOT REMOVE THIS. It looks like a compileall workaround -- that is how it was
# originally described -- but its load-bearing effect is to make /code/.venv an
# *overlay* virtualenv: writable site-packages of its own, plus
# `include-system-site-packages = true` so the base image's interpreter packages
# remain importable underneath. Step 19's `pip install` then lands in the overlay
# and layers over the base image rather than overwriting it.
#
# Without this, step 19 installs straight onto the site-packages that the
# platform's own serving harness imports from, and any unpinned requirement is
# free to move a package the harness depends on. That happened on 2026-07-28:
# the resolve advanced grpcio 1.82.1 -> 1.83.0 and
# opentelemetry-resourcedetector-gcp 1.12.0a0 -> 1.14.0, and newly injected
# httpx/httpcore/packaging that the base image had been satisfying. The build
# stayed green and the image pushed, but the container then died during harness
# import -- before uvicorn logged its first line -- so the deploy failed with
# "failed to start and cannot serve traffic" and *zero* stderr to debug from.
#
# The base image does ship a usable .venv/bin/python for compileall on its own,
# so the build gives no signal that this is missing. Only the runtime does.
_OVERLAY_VENV_SCRIPT = """\
#!/bin/bash
# Create an overlay virtualenv at /code/.venv so the agent's dependency install
# layers over the base image instead of replacing its site-packages.
#
# `include-system-site-packages = true` keeps the base image's packages (and the
# platform's serving harness) importable, while site-packages here is writable by
# appuser -- a bare symlink would make site.getsitepackages()[0] resolve to the
# root-owned /usr/local/lib/python3.12/site-packages and fail with PermissionError.
set -e
PYTHON3=$(which python3)
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
mkdir -p /code/.venv/bin
mkdir -p /code/.venv/lib/python${PY_VER}/site-packages
ln -sf "$PYTHON3" /code/.venv/bin/python
ln -sf "$PYTHON3" /code/.venv/bin/python3
cat > /code/.venv/pyvenv.cfg << PYCFG
home = $(dirname $PYTHON3)
include-system-site-packages = true
PYCFG
echo "Created .venv virtualenv (site-packages: /code/.venv/lib/python${PY_VER}/site-packages)"
"""

# Path of the script within the staging dir. The platform looks for
# `./installation_scripts` at the root of the extracted dependencies tarball, so
# this must also be listed in `extra_packages` -- `build_options` alone only
# covers the SDK create path, not a Terraform `package_spec` deploy built by
# `--build-only`.
_OVERLAY_VENV_SCRIPT_PATH = "installation_scripts/create_venv.sh"


def _write_overlay_venv_script(staging_dir: str) -> None:
    """Write the overlay-venv installation script into ``staging_dir``.

    See ``_OVERLAY_VENV_SCRIPT`` for why this is required.
    """
    script_path = os.path.join(staging_dir, _OVERLAY_VENV_SCRIPT_PATH)
    os.makedirs(os.path.dirname(script_path), exist_ok=True)
    with open(script_path, "w") as f:
        f.write(_OVERLAY_VENV_SCRIPT)
    os.chmod(script_path, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP)


def _ge_deploy(
    *,
    project: str,
    app_id: str,
    agent_name: str,
    display_name: str,
    description: str,
    reasoning_engine_name: str,
    oauth_client_id: str,
    oauth_client_secret: str,
) -> None:
    """Register an Agent Engine agent in Gemini Enterprise."""
    import google.auth
    import google.auth.transport.requests

    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())
    access_token = credentials.token

    base_url = f"https://global-discoveryengine.googleapis.com/v1alpha/projects/{project}/locations/global"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": project,
    }

    # Step 1: Delete existing agents by display name (must happen before
    # authorization delete, because authorizations cannot be deleted while
    # linked to an agent).  Matching by displayName instead of reasoning
    # engine reference ensures cleanup works across redeploys that create
    # new reasoning engines.
    agents_url = f"{base_url}/collections/default_collection/engines/{app_id}/assistants/default_assistant/agents"
    print(f"Checking for existing agent in Gemini Enterprise engine '{app_id}'...")
    list_req = urllib.request.Request(agents_url, headers=headers)
    try:
        with urllib.request.urlopen(list_req) as resp:
            list_resp = json.loads(resp.read())
            for agent in list_resp.get("agents", []):
                if agent.get("displayName") == display_name:
                    existing_name = agent["name"]
                    print(f"  Deleting existing agent: {existing_name}...")
                    del_agent_url = f"https://global-discoveryengine.googleapis.com/v1alpha/{existing_name}"
                    del_agent_req = urllib.request.Request(del_agent_url, headers=headers, method="DELETE")
                    with urllib.request.urlopen(del_agent_req) as del_resp:
                        del_resp.read()
                    print("  Deleted.")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"WARNING: could not list/delete agents: {e.code} {body}", file=sys.stderr)

    # Step 2: Delete existing authorizations by prefix (now unlinked).
    # Handles both legacy non-suffixed IDs (e.g. "mortgage-agent") and
    # timestamp-suffixed IDs (e.g. "mortgage-agent_1712505600000").
    auth_prefix = f"projects/{project}/locations/global/authorizations/{agent_name}"
    print(f"Cleaning up authorizations matching '{agent_name}*'...")
    list_auth_url = f"{base_url}/authorizations"
    list_auth_req = urllib.request.Request(list_auth_url, headers=headers)
    try:
        with urllib.request.urlopen(list_auth_req) as resp:
            auth_list = json.loads(resp.read())
            for auth in auth_list.get("authorizations", []):
                auth_name = auth.get("name", "")
                if auth_name == auth_prefix or auth_name.startswith(f"{auth_prefix}_"):
                    print(f"  Deleting authorization: {auth_name}...")
                    del_auth_url = f"https://global-discoveryengine.googleapis.com/v1alpha/{auth_name}"
                    del_auth_req = urllib.request.Request(del_auth_url, headers=headers, method="DELETE")
                    try:
                        with urllib.request.urlopen(del_auth_req) as del_resp:
                            del_resp.read()
                        print("  Deleted.")
                    except urllib.error.HTTPError as e:
                        body = e.read().decode()
                        print(f"WARNING: delete authorization failed: {e.code} {body}", file=sys.stderr)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"WARNING: could not list authorizations: {e.code} {body}", file=sys.stderr)

    # Step 3: Create authorization with timestamp-suffixed ID.
    # The Gemini Enterprise backend requires this format for proper OAuth token
    # storage; simple IDs cause an infinite consent loop.
    auth_id = f"{agent_name}_{int(time.time() * 1000)}"
    auth_resource_name = f"projects/{project}/locations/global/authorizations/{auth_id}"
    auth_url = f"{base_url}/authorizations?authorizationId={auth_id}"
    authorization_uri = (
        "https://accounts.google.com/o/oauth2/v2/auth"
        f"?client_id={oauth_client_id}"
        "&redirect_uri=https%3A%2F%2Fvertexaisearch.cloud.google.com%2Fstatic%2Foauth%2Foauth.html"
        "&scope=https://www.googleapis.com/auth/cloud-platform"
        "&include_granted_scopes=true"
        "&response_type=code"
        "&access_type=offline"
        "&prompt=consent"
    )
    auth_body = json.dumps(
        {
            "displayName": auth_id,
            "serverSideOauth2": {
                "clientId": oauth_client_id,
                "clientSecret": oauth_client_secret,
                "tokenUri": "https://oauth2.googleapis.com/token",
                "authorizationUri": authorization_uri,
            },
        }
    ).encode()

    print(f"Creating authorization '{auth_id}'...")
    auth_req = urllib.request.Request(auth_url, data=auth_body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(auth_req) as resp:
            auth_resp = json.loads(resp.read())
            auth_resource_name = auth_resp.get("name", auth_resource_name)
            print(f"  Authorization created: {auth_resource_name}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"ERROR creating authorization: {e.code} {body}", file=sys.stderr)
        sys.exit(1)

    # Step 4: Create agent registration
    agent_body = json.dumps(
        {
            "displayName": display_name,
            "description": description,
            "adk_agent_definition": {
                "provisioned_reasoning_engine": {
                    "reasoning_engine": reasoning_engine_name,
                },
            },
            "authorization_config": {
                "tool_authorizations": [
                    auth_resource_name,
                ],
            },
            "sharingConfig": {
                "scope": "ALL_USERS",
            },
            "agentInvocationSpec": {
                "invocationMode": "AUTOMATIC",
            },
        }
    ).encode()

    print(f"Registering agent in Gemini Enterprise engine '{app_id}'...")
    agent_req = urllib.request.Request(agents_url, data=agent_body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(agent_req) as resp:
            agent_resp = json.loads(resp.read())
            agent_resource = agent_resp.get("name", "unknown")
            print(f"  Agent registered: {agent_resource}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"ERROR registering agent: {e.code} {body}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Deploy mortgage assistant agent to Vertex AI Agent Engine")
    parser.add_argument(
        "--project",
        default=os.environ.get("PROJECT_ID"),
        help="GCP project ID (default: $PROJECT_ID)",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("REGION", "us-central1"),
        help="GCP region (default: $REGION or us-central1)",
    )
    parser.add_argument(
        "--staging-bucket",
        default=None,
        help="GCS bucket for staging (default: gs://PROJECT-staging)",
    )
    parser.add_argument(
        "--display-name",
        default="Mortgage Assistant Agent",
        help="Display name for the deployed agent",
    )
    parser.add_argument(
        "--update",
        default=None,
        metavar="RESOURCE_NAME",
        help="Update an existing agent in-place instead of creating a new one. "
        "Pass the full resource name "
        "(e.g. projects/PROJECT/locations/REGION/reasoningEngines/ENGINE_ID)",
    )
    parser.add_argument(
        "--network-attachment",
        default=None,
        help="Network attachment for PSC Interface (full path or name)",
    )
    parser.add_argument(
        "--dns-peering-domain",
        default=None,
        help="DNS domain for PSC-I DNS peering (e.g. internal.example.com.)",
    )
    parser.add_argument(
        "--dns-peering-target-project",
        default=None,
        help="Project hosting the target VPC network for DNS peering",
    )
    parser.add_argument(
        "--dns-peering-target-network",
        default=None,
        help="VPC network name for DNS peering",
    )
    parser.add_argument(
        "--agent-gateway",
        default=None,
        help="Agent Gateway resource name (e.g. projects/PROJECT/locations/REGION/agentGateways/GATEWAY_ID)",
    )
    parser.add_argument(
        "--enable-agent-identity",
        action="store_true",
        help="Enable agent identity (per-agent least-privilege credentials)",
    )
    parser.add_argument(
        "--ge-deploy",
        action="store_true",
        help="Register agent in Gemini Enterprise after deploy",
    )
    parser.add_argument(
        "--ge-deploy-only",
        default=None,
        metavar="RESOURCE_NAME",
        help="Register an existing reasoning engine in Gemini Enterprise without "
        "redeploying. Pass the full resource name "
        "(e.g. projects/PROJECT/locations/REGION/reasoningEngines/ENGINE_ID)",
    )
    parser.add_argument(
        "--app-id",
        default=None,
        help="Gemini Enterprise engine ID (required with --ge-deploy)",
    )
    parser.add_argument(
        "--oauth-client-id",
        default=os.environ.get("OAUTH_CLIENT_ID"),
        help="OAuth2 client ID (default: $OAUTH_CLIENT_ID, required with --ge-deploy)",
    )
    parser.add_argument(
        "--oauth-client-secret",
        default=os.environ.get("OAUTH_CLIENT_SECRET"),
        help="OAuth2 client secret (default: $OAUTH_CLIENT_SECRET, required with --ge-deploy)",
    )
    parser.add_argument(
        "--model",
        default="gemini-3.5-flash-lite",
        help="Gemini model name for the agent (default: gemini-3.5-flash-lite)",
    )
    parser.add_argument(
        "--model-endpoint-location",
        default="global",
        help=(
            "Location passed to the agent as GOOGLE_CLOUD_LOCATION; controls which "
            "Vertex AI Gemini endpoint the model calls (default: global). Use a "
            "specific region (e.g. us-central1) to pin to a regional endpoint."
        ),
    )
    parser.add_argument(
        "--registry-filter",
        default=None,
        help=(
            "Optional Google API list-filter expression passed to the agent as "
            "MCP_REGISTRY_FILTER, scoping which mcpServers the agent picks up "
            "from the registry at startup."
        ),
    )
    parser.add_argument(
        "--registry-endpoint",
        default=None,
        help=(
            "Override the Agent Registry base URL the agent calls. When "
            "unset, MCP_REGISTRY_ENDPOINT is not exported and the agent "
            "uses ADK's built-in default "
            "(https://agentregistry.googleapis.com/v1alpha) — currently "
            "the only endpoint that serves mcpServers. Set this to a "
            "regional URL (e.g. https://<region>-agentregistry.googleapis.com/v1alpha) "
            "once those endpoints exist. Passed to the agent as "
            "MCP_REGISTRY_ENDPOINT."
        ),
    )
    parser.add_argument(
        "--agent-name",
        default="mortgage-agent",
        help="Discovery Engine authorization/agent name (default: mortgage-agent)",
    )
    parser.add_argument(
        "--mcp-invoker-sa",
        default=os.environ.get("MCP_INVOKER_SA_EMAIL"),
        help=(
            "Email of the service account the deployed agent impersonates to mint "
            "OIDC ID tokens for MCP Cloud Run calls. The agent's identity must hold "
            "roles/iam.serviceAccountTokenCreator on this SA, and this SA must hold "
            "roles/run.invoker on each MCP Cloud Run service. Sourced from terraform "
            "output `agent_mcp_invoker_email`. Default: $MCP_INVOKER_SA_EMAIL, "
            "falling back to agent-mcp-invoker@<project>.iam.gserviceaccount.com."
        ),
    )
    parser.add_argument(
        "--build-only",
        action="store_true",
        help=(
            "Package and upload the agent artifacts (pickle, dependencies, "
            "requirements) to the staging bucket and write a manifest JSON, "
            "WITHOUT creating/updating a reasoning engine. Used to feed the "
            "Terraform google_vertex_ai_reasoning_engine package_spec."
        ),
    )
    parser.add_argument(
        "--artifacts-out",
        default=None,
        help=(
            "Path to write the build-only manifest JSON (artifact layout + "
            "python_version + agent_framework + class_methods). Relative paths "
            "resolve against the current directory. Default: "
            "<repo>/build/agent_artifacts.json."
        ),
    )
    parser.add_argument(
        "--gcs-dir",
        default="agent_engine",
        help="Staging-bucket subdirectory for the uploaded artifacts (default: agent_engine).",
    )
    args = parser.parse_args()

    if not args.project:
        parser.error("--project is required (or set $PROJECT_ID)")

    # Fall back to the SA terraform creates in modules/agent-engine, whose
    # account_id is hardcoded to "agent-mcp-invoker" — so the email is fully
    # determined by the project and doesn't need `terraform output`. Derived
    # from args.project (which itself defaults to $PROJECT_ID) so an explicit
    # --project is honoured too. Deploys that don't use MCP-over-Cloud-Run are
    # unaffected: the agent only impersonates this SA when it calls one.
    #
    # --project is accepted as either a project ID or a project number, but SA
    # emails only exist in the ID form. Deriving from a number would produce an
    # address that never resolves, and because the derived value is always
    # truthy it would set MCP_INVOKER_SA_EMAIL and push the failure out to an
    # opaque token-mint error at runtime. Leave it unset instead, which is the
    # documented path: the agent logs an explicit "MCP_INVOKER_SA_EMAIL is not
    # set" warning at discovery time.
    if not args.mcp_invoker_sa:
        if str(args.project).isdigit():
            print(
                f"WARNING: --project is a project number ({args.project}), so the "
                "default --mcp-invoker-sa cannot be derived (SA emails require the "
                "project ID). Pass --mcp-invoker-sa explicitly if this agent calls "
                "IAM-protected MCP services.",
                file=sys.stderr,
            )
        else:
            args.mcp_invoker_sa = f"agent-mcp-invoker@{args.project}.iam.gserviceaccount.com"

    ge_deploy_needed = args.ge_deploy or args.ge_deploy_only
    oauth_client_secret = None
    if ge_deploy_needed:
        if not args.app_id:
            parser.error("--app-id is required when using --ge-deploy or --ge-deploy-only")
        if not args.oauth_client_id:
            parser.error(
                "--oauth-client-id is required when using --ge-deploy or --ge-deploy-only (or set $OAUTH_CLIENT_ID)"
            )
        oauth_client_secret = args.oauth_client_secret
        if not oauth_client_secret:
            parser.error(
                "--oauth-client-secret is required when using --ge-deploy or --ge-deploy-only "
                "(or set $OAUTH_CLIENT_SECRET)"
            )

    description = (
        "ADK mortgage assistant agent connecting to legacy DMS, income verification, and corporate email services."
    )

    # --ge-deploy-only: skip Agent Engine deploy, just register in Gemini Enterprise
    if args.ge_deploy_only:
        reasoning_engine_name = args.ge_deploy_only
        print("Registering existing reasoning engine in Gemini Enterprise...")
        print(f"  Project:          {args.project}")
        print(f"  Reasoning engine: {reasoning_engine_name}")
        print(f"  Display name:     {args.display_name}")
        print(f"  App ID:           {args.app_id}")
        print()
        assert oauth_client_secret is not None
        _ge_deploy(
            project=args.project,
            app_id=args.app_id,
            agent_name=args.agent_name,
            display_name=args.display_name,
            description=description,
            reasoning_engine_name=reasoning_engine_name,
            oauth_client_id=args.oauth_client_id,
            oauth_client_secret=oauth_client_secret,
        )
        return

    staging_bucket = args.staging_bucket or f"gs://{args.project}-staging"

    # Ensure the agent package is importable
    agent_dir = os.path.dirname(os.path.abspath(__file__))
    if agent_dir not in sys.path:
        sys.path.insert(0, agent_dir)

    print("Deploying mortgage assistant agent to Agent Engine...")
    print(f"  Project:        {args.project}")
    print(f"  Region:         {args.region}")
    print(f"  Model:          {args.model}")
    print(f"  Model endpoint: {args.model_endpoint_location}")
    print(f"  Registry scope: {args.project}/{args.region}")
    if args.registry_endpoint:
        print(f"  Registry endpoint (override): {args.registry_endpoint}")
    if args.registry_filter:
        print(f"  Registry filter: {args.registry_filter}")
    print(f"  Display name:   {args.display_name}")
    print(f"  Staging bucket: {staging_bucket}")
    print(f"  Mode:           {'update' if args.update else 'create'}")
    if args.agent_gateway:
        print(f"  Agent Gateway:  {args.agent_gateway}")
    if args.update:
        print(f"  Resource name:  {args.update}")
    if args.network_attachment:
        print(f"  Network attachment: {args.network_attachment}")
    if args.enable_agent_identity:
        print("  Agent identity:     enabled")
    if args.mcp_invoker_sa:
        print(f"  MCP invoker SA:     {args.mcp_invoker_sa}")
    print()

    # Configure the agent module's runtime environment. These are read at
    # `from agent.agent import root_agent` time below, so they must be set
    # before the import — not just in the deployed agent's env_vars.
    os.environ["MODEL_NAME"] = args.model
    os.environ["MCP_REGISTRY_PROJECT"] = args.project
    os.environ["MCP_REGISTRY_LOCATION"] = args.region
    if args.registry_filter:
        os.environ["MCP_REGISTRY_FILTER"] = args.registry_filter
    if args.registry_endpoint:
        os.environ["MCP_REGISTRY_ENDPOINT"] = args.registry_endpoint
    if args.mcp_invoker_sa:
        os.environ["MCP_INVOKER_SA_EMAIL"] = args.mcp_invoker_sa

    import vertexai

    vertexai.init(
        project=args.project,
        location=args.region,
        staging_bucket=staging_bucket,
    )

    client = vertexai.Client(
        project=args.project,
        location=args.region,
        http_options=dict(api_version="v1beta1"),
    )

    from agent.agent import root_agent
    from agent.otel_setup import InstrumentedAdkApp

    app = InstrumentedAdkApp(agent=root_agent, enable_tracing=True)

    # Build PSC-I and agent identity config
    config = {}
    if args.network_attachment:
        psc_config = {"network_attachment": args.network_attachment}
        if args.dns_peering_domain:
            psc_config["dns_peering_configs"] = [
                {
                    "domain": args.dns_peering_domain,
                    "target_project": args.dns_peering_target_project or args.project,
                    "target_network": args.dns_peering_target_network,
                }
            ]
        config["psc_interface_config"] = psc_config
    if args.enable_agent_identity:
        config["identity_type"] = "AGENT_IDENTITY"
    if args.agent_gateway:
        config["agent_gateway_config"] = {"agent_to_anywhere_config": {"agent_gateway": args.agent_gateway}}

    agent_src = os.path.join(agent_dir, "agent")
    staging_dir = tempfile.mkdtemp(prefix="agent_deploy_")
    original_cwd = os.getcwd()

    try:
        shutil.copytree(
            agent_src,
            os.path.join(staging_dir, "agent"),
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"),
        )
        _write_overlay_venv_script(staging_dir)

        os.chdir(staging_dir)

        deploy_config = dict(
            staging_bucket=staging_bucket,
            requirements=[
                # Upper-bound pin keeps the container on a release where
                # `vertexai.agent_engines.AdkApp` (the public import used by
                # agent/otel_setup.py) resolves the same class the operator
                # pickled. Unpinned, PyPI advanced to 1.153.1 which had already
                # removed the older `vertexai.agent_engines.templates.adk` path
                # and broke unpickle in the container. The `[adk]` extra is
                # omitted because google-adk is pinned explicitly below; the
                # extra would just re-declare the same dep with a looser
                # range. Keep aligned with pyproject.toml.
                "google-cloud-aiplatform[agent_engines]>=1.149.0,<1.154.0",
                # Pin google-adk to a tagged PyPI release (was previously
                # tracking adk-python@main, which started publishing 2.0.0b1
                # and conflicted with google-cloud-aiplatform's [adk] extra).
                # The [a2a,agent-identity] extras pull a2a-sdk and
                # google-cloud-iamconnectorcredentials at the versions
                # google-adk itself requires — without them registry
                # discovery fails on `cannot import name 'TransportProtocol'`
                # (a2a) or
                # `No module named google.cloud.iamconnectorcredentials_v1alpha`.
                # Keep aligned with pyproject.toml.
                "google-adk[a2a,agent-identity]==1.34.0",
                "google-auth>=2.0",
                "cloudpickle",
                "pydantic",
                "opentelemetry-instrumentation-google-genai",
                "opentelemetry-exporter-gcp-logging",
                # --- Transitive pins -------------------------------------
                # Nothing above changes version between builds, but their
                # transitives resolve fresh every time, so an unchanged source
                # tree produces a different container week to week. These are
                # the twelve that drifted between the last known-good build
                # (2026-07-14, build c7e12542) and 2026-07-28, pinned back to
                # the known-good versions. Reproducing that resolve exactly is
                # the point -- the 2026-07-28 container died during harness
                # import, before uvicorn logged a line, leaving no stderr.
                #
                # The most likely culprit is the opentelemetry-*-gcp skew:
                # resourcedetector-gcp went 1.12.0a0 -> 1.14.0 while the
                # exporters stayed on 1.12.0a0, and GCP resource detection runs
                # during startup. grpcio 1.82.1 -> 1.83.0 is the other
                # candidate. Both are pinned here rather than bisected, because
                # each deploy round trip costs ~9 minutes.
                #
                # These are transitives, so they are deliberately NOT mirrored
                # into pyproject.toml -- that file describes the local dev
                # environment, and uv.lock already pins it.
                "aiohttp==3.14.1",
                "google-cloud-bigtable==2.40.0",
                "google-cloud-secret-manager==2.29.0",
                "greenlet==3.5.3",
                "grpcio==1.82.1",
                "grpcio-status==1.81.1",
                "joserfc==1.7.3",
                "mcp==1.28.1",
                "opentelemetry-resourcedetector-gcp==1.12.0a0",
                "sse-starlette==3.4.5",
                # opentelemetry-instrumentation (pulled in transitively by
                # opentelemetry-instrumentation-google-genai above) constrains
                # wrapt<2.0.0,>=1.0.0, so a 2.x pin here is unsatisfiable and
                # either fails resolution or backtracks otel onto some other
                # version. 1.17.3 is what uv.lock resolves to.
                "wrapt==1.17.3",
                "yarl==1.24.2",
            ],
            # The script must be in extra_packages, not just build_options:
            # build_options is only honoured by the SDK create path, while a
            # terraform package_spec deploy consumes the dependencies tarball
            # directly. Listing it here puts it in the tarball either way, which
            # is all Step 16 needs to find ./installation_scripts. Both are kept
            # so the imperative path behaves identically.
            extra_packages=["agent", _OVERLAY_VENV_SCRIPT_PATH],
            build_options={"installation_scripts": [_OVERLAY_VENV_SCRIPT_PATH]},
            env_vars={
                # Make denied MCP tool calls (gateway 403) fail fast instead of
                # hanging the turn as a broken-stream TaskGroup/TimeoutError.
                "ADK_ENABLE_MCP_GRACEFUL_ERROR_HANDLING": "true",
                "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY": "true",
                "GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES": "false",
                "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT": "true",
                "OTEL_TRACES_SAMPLER": "parentbased_traceidratio",
                "OTEL_TRACES_SAMPLER_ARG": "1.0",
                "GOOGLE_GENAI_USE_VERTEXAI": "True",
                "GOOGLE_CLOUD_LOCATION": args.model_endpoint_location,
                "MODEL_NAME": args.model,
                "MCP_REGISTRY_PROJECT": args.project,
                "MCP_REGISTRY_LOCATION": args.region,
                **({"MCP_REGISTRY_FILTER": args.registry_filter} if args.registry_filter else {}),
                **({"MCP_REGISTRY_ENDPOINT": args.registry_endpoint} if args.registry_endpoint else {}),
                **({"MCP_INVOKER_SA_EMAIL": args.mcp_invoker_sa} if args.mcp_invoker_sa else {}),
            },
            display_name=args.display_name,
            description=description,
            min_instances=2,
            resource_limits={"cpu": "4", "memory": "8Gi"},
        )

        if config:
            deploy_config.update(config)

        if args.build_only:
            # Stage the exact artifacts client.agent_engines.create() would
            # upload (same pickle, deps tarball, requirements, class_methods),
            # but do NOT create an engine. Terraform's package_spec consumes
            # the resulting GCS URIs + class_methods via the manifest below.
            # These _-prefixed helpers are SDK internals, safe only because the
            # project pins google-cloud-aiplatform <1.154.
            import json as _json

            from vertexai._genai import _agent_engines_utils as _aeu

            print(f"Build-only: staging artifacts to {staging_bucket}/{args.gcs_dir}/ (no engine create)...")
            _aeu._prepare(
                agent=app,
                requirements=deploy_config["requirements"],
                extra_packages=deploy_config["extra_packages"],
                project=args.project,
                location=args.region,
                staging_bucket=staging_bucket,
                gcs_dir_name=args.gcs_dir,
            )
            class_methods = [
                _aeu._to_dict(s)
                for s in _aeu._generate_class_methods_spec_or_raise(
                    agent=app,
                    operations=_aeu._get_registered_operations(agent=app),
                )
            ]
            # Deliberately bucket-free: the manifest records only the artifact
            # layout, so terraform composes the gs:// URIs from its own
            # project_id/agent_staging_bucket. Keeps the file portable between
            # projects (and safe to regenerate) instead of pinning one bucket.
            manifest = {
                "python_version": f"{sys.version_info.major}.{sys.version_info.minor}",
                "agent_framework": _aeu._get_agent_framework(agent_framework=None, agent=app),
                "gcs_dir": args.gcs_dir,
                "pickle_filename": _aeu._BLOB_FILENAME,
                "dependencies_filename": _aeu._EXTRA_PACKAGES_FILE,
                "requirements_filename": _aeu._REQUIREMENTS_FILE,
                "class_methods": class_methods,
            }
            if args.artifacts_out:
                out_path = (
                    args.artifacts_out
                    if os.path.isabs(args.artifacts_out)
                    else os.path.join(original_cwd, args.artifacts_out)
                )
            else:
                out_path = os.path.join(agent_dir, "..", "..", "build", "agent_artifacts.json")
            out_path = os.path.abspath(out_path)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w") as mf:
                _json.dump(manifest, mf, indent=2)
            print(f"Staged artifacts and wrote manifest ({len(class_methods)} class methods): {out_path}")
            return

        if args.update:
            engine = client.agent_engines.update(name=args.update, agent=app, config=deploy_config)
        elif args.enable_agent_identity:
            # 1. Create empty agent shell
            print("Deploying with AGENT_IDENTITY. Initiating empty bootstrap to prevent telemetry blocks...")
            empty_config = {
                "display_name": args.display_name,
                "description": description,
                "identity_type": "AGENT_IDENTITY",
            }

            print("Step 1: Creating identity-only agent shell...")
            engine = client.agent_engines.create(config=empty_config)
            reasoning_engine_name = engine.api_resource.name
            agent_id = reasoning_engine_name.split("/")[-1]
            print(f"Identity shell successfully created. ID: {agent_id}")

            # 2. Grant permissions.
            #
            # The roles/iap.egressor bindings this step used to apply via
            # scripts/grant_agent_mcp_egress.sh are now owned by terraform (see
            # terraform/modules/agent-registry-endpoints). Terraform can't know
            # this agent's id until it exists, so wire it up after the fact:
            # set iap_egressor_members and re-apply. Until then the agent has an
            # identity but no egress, and gateway calls will be denied by IAP.
            print("\nStep 2: Egress permissions are managed by terraform.")
            print("  Add this agent's identity to iap_egressor_members and re-apply:")
            print(
                "    principal://agents.global.org-${ORG_ID}.system.id.goog/resources/aiplatform"
                f"/projects/${{PROJECT_NUMBER}}/locations/{args.region}/reasoningEngines/{agent_id}"
            )
            print("  (or set deploy_reasoning_engine=true and let terraform own the engine outright)")

            # 3. Update the agent with the actual pickled code
            print(f"\nStep 3: Updating reasoning engine {reasoning_engine_name} with actual application code...")
            engine = client.agent_engines.update(name=reasoning_engine_name, agent=app, config=deploy_config)
        else:
            engine = client.agent_engines.create(agent=app, config=deploy_config)
    finally:
        os.chdir(original_cwd)
        shutil.rmtree(staging_dir, ignore_errors=True)

    reasoning_engine_name = engine.api_resource.name

    print()
    if args.update:
        print(f"Agent updated: {reasoning_engine_name}")
    else:
        print(f"Agent deployed: {reasoning_engine_name}")
        print()
        print("Set the resource name in your terraform.tfvars:")
        print(f'  agent_engine_resource_name = "{reasoning_engine_name}"')
        if args.enable_agent_identity:
            print("\nAgent identity enabled. Grant IAM to the agent's principal shown above.")

    if args.ge_deploy:
        print()
        assert oauth_client_secret is not None
        _ge_deploy(
            project=args.project,
            app_id=args.app_id,
            agent_name=args.agent_name,
            display_name=args.display_name,
            description=description,
            reasoning_engine_name=reasoning_engine_name,
            oauth_client_id=args.oauth_client_id,
            oauth_client_secret=oauth_client_secret,
        )


if __name__ == "__main__":
    main()
