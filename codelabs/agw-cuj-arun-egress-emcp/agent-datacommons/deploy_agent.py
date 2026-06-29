#!/usr/bin/env python3
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

# Version 12

import argparse
import importlib
import json
import os
import shutil
import stat
import sys
import tempfile
import time
from urllib.parse import urlparse

import google.auth
import google.auth.transport.requests
import requests


def register_to_ge(
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
    """Register an Agent Engine agent in Gemini Enterprise.

    Includes creation of authorization to prevent consent loops.
    """
    credentials, _ = google.auth.default()
    auth_req = google.auth.transport.requests.Request()
    credentials.refresh(auth_req)
    access_token = credentials.token

    base_url = f"https://global-discoveryengine.googleapis.com/v1alpha/projects/{project}/locations/global"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": project,
    }

    # Create authorization with timestamp-suffixed ID (avoids consent loop)
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
    
    auth_body = {
        "displayName": auth_id,
        "serverSideOauth2": {
            "clientId": oauth_client_id,
            "clientSecret": oauth_client_secret,
            "tokenUri": "https://oauth2.googleapis.com/token",
            "authorizationUri": authorization_uri,
        },
    }

    print(f"Creating authorization '{auth_id}'...")
    try:
        response = requests.post(auth_url, headers=headers, json=auth_body)
        response.raise_for_status()
        auth_resp = response.json()
        auth_resource_name = auth_resp.get("name", auth_resource_name)
        print(f"  Authorization created: {auth_resource_name}")
    except requests.exceptions.RequestException as e:
        print(f"ERROR creating authorization: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        sys.exit(1)

    # Create agent registration
    agents_url = f"{base_url}/collections/default_collection/engines/{app_id}/assistants/default_assistant/agents"
    agent_body = {
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

    print(f"Registering agent in Gemini Enterprise engine '{app_id}'...")
    try:
        response = requests.post(agents_url, headers=headers, json=agent_body)
        response.raise_for_status()
        agent_resp = response.json()
        print(f"  Agent registered: {agent_resp.get('name', 'unknown')}")
    except requests.exceptions.RequestException as e:
        print(f"ERROR registering agent: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Deploy ADK Agent to Agent Engine")
    parser.add_argument("--project", required=True, help="Google Cloud Project ID")
    parser.add_argument("--region", default="us-central1", help="Vertex AI Region")
    parser.add_argument("--src-dir", required=True, help="Directory containing agent code (must contain agent.py)")
    parser.add_argument("--staging-bucket", help="GCS bucket for staging (default: gs://PROJECT-staging)")
    parser.add_argument("--ge-auth-name", default="my-agent", help="Internal name for GE authorization (default: my-agent)")
    parser.add_argument("--display-name", default="My ADK Agent", help="Display name for the deployed agent")
    parser.add_argument("--description", default="An ADK agent.", help="Agent description (applies to both Reasoning Engine and GE)")
    # Advanced Options
    parser.add_argument("--network-attachment", help="Network attachment for PSC Interface")
    parser.add_argument("--agent-gateway-egress", help="Egress Agent Gateway resource name (Agent-to-Anywhere)")
    parser.add_argument("--agent-gateway-ingress", help="Ingress Agent Gateway resource name (Client-to-Agent)")
    parser.add_argument("--enable-agent-identity", action="store_true", help="Enable Agent Identity")
    parser.add_argument("--network-project", help="Project ID where network resources reside (defaults to --project)")
    parser.add_argument("--target-network", help="Target network name or URI for DNS peering")
    parser.add_argument("--dns-domains", help="Comma-separated list of domains for DNS peering")
    parser.add_argument("--mcp-server-url", help="MCP Server URL to set in environment")
    parser.add_argument("--data-bucket", help="GCS bucket name for customer data")
    parser.add_argument("--endpoint-url", help="Endpoint URL for Quote of the Day service")
    parser.add_argument("--re-custom-sa", help="Custom service account for Reasoning Engine")
    parser.add_argument("--enable-telemetry", action="store_true", help="Enable native Reasoning Engine telemetry")
    parser.add_argument("--allow-token-sharing", action="store_true", help="Allow agent identity token sharing for GCP services (disables bound token sharing)")
    parser.add_argument("-e", "--env-var", action="append", help="Additional environment variables to pass to deployed engine (format: KEY=VALUE)")
    
    # Gemini Enterprise
    parser.add_argument("--ge-deploy", action="store_true", help="Register with Gemini Enterprise after deploy")
    parser.add_argument("--app-id", help="Gemini Enterprise App ID")
    parser.add_argument("--oauth-client-id", help="OAuth2 client ID")
    parser.add_argument("--oauth-client-secret", help="OAuth2 client secret")
    
    args = parser.parse_args()

    if args.ge_deploy:
        if not args.app_id or not args.oauth_client_id or not args.oauth_client_secret:
            parser.error("Gemini Enterprise deployment requires --app-id, --oauth-client-id, and --oauth-client-secret")

    staging_bucket = args.staging_bucket or f"gs://{args.project}-staging"
    if not staging_bucket.startswith("gs://"):
        staging_bucket = f"gs://{staging_bucket}"

    print("Initializing Vertex AI...")
    import vertexai
    vertexai.init(
        project=args.project,
        location=args.region,
        staging_bucket=staging_bucket,
    )

    # Initialize client with correct API version if Agent Identity is requested
    if args.enable_agent_identity:
        from vertexai import types
        client = vertexai.Client(
            project=args.project,
            location=args.region,
            http_options=dict(api_version="v1beta1")
        )
    else:
        client = vertexai.Client(project=args.project, location=args.region)

    # Staging Trick: Copy source to a temp directory named 'agent'
    staging_dir = tempfile.mkdtemp(prefix="agent_deploy_")
    original_cwd = os.getcwd()
    
    try:
        src_abs_path = os.path.abspath(args.src_dir)
        agent_dest = os.path.join(staging_dir, "agent")
        
        print(f"Staging agent code from {src_abs_path} to {agent_dest}...")
        shutil.copytree(
            src_abs_path,
            agent_dest,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache", ".venv"),
        )

        # Add staging dir to path to import the newly copied agent
        if staging_dir not in sys.path:
            sys.path.insert(0, staging_dir)

        # Import agent after vertexai.init
        try:
            from vertexai.agent_engines import AdkApp
            agent_module = importlib.import_module("agent.agent")
            root_agent = agent_module.root_agent
            app = AdkApp(agent=root_agent)
        except ImportError as e:
            print(f"ERROR: Failed to import agent from staged directory: {e}")
            sys.exit(1)

        # Create installation_scripts/ with workaround for platform bug
        scripts_dir = os.path.join(staging_dir, "installation_scripts")
        os.makedirs(scripts_dir)
        script_path = os.path.join(scripts_dir, "create_venv.sh")
        with open(script_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("set -e\n")
            f.write("PYTHON3=$(which python3)\n")
            f.write("PY_VER=$(python3 -c 'import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")')\n")
            f.write("mkdir -p /code/.venv/bin\n")
            f.write("mkdir -p /code/.venv/lib/python${PY_VER}/site-packages\n")
            f.write('ln -sf "$PYTHON3" /code/.venv/bin/python\n')
            f.write('ln -sf "$PYTHON3" /code/.venv/bin/python3\n')
            f.write("cat > /code/.venv/pyvenv.cfg << PYCFG\n")
            f.write("home = $(dirname $PYTHON3)\n")
            f.write("include-system-site-packages = true\n")
            f.write("PYCFG\n")
        os.chmod(script_path, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP)

        os.chdir(staging_dir)

        # Read requirements from pyproject.toml
        import tomllib
        requirements = []
        try:
            # Look for pyproject.toml relative to this script's directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            pyproject_path = os.path.join(script_dir, "pyproject.toml")
            with open(pyproject_path, "rb") as f:
                pyproject = tomllib.load(f)
                requirements = pyproject.get("project", {}).get("dependencies", [])
                print(f"Loaded {len(requirements)} requirements from {pyproject_path}")
        except FileNotFoundError:
            print(f"WARNING: pyproject.toml not found at {pyproject_path}. Using fallback requirements.")
            requirements = [
                "google-cloud-aiplatform[adk,agent_engines]",
                "google-auth>=2.0",
            ]

        # Build config
        deploy_config = {
            "display_name": args.display_name,
            "description": args.description,
            "staging_bucket": staging_bucket,
            "requirements": requirements,
            "extra_packages": [
                "agent",
                "installation_scripts/create_venv.sh",
            ],
            "build_options": {
                "installation_scripts": [
                    "installation_scripts/create_venv.sh",
                ],
            },
            "env_vars": {
                "GOOGLE_GENAI_USE_VERTEXAI": "True",
                "GOOGLE_API_USE_CLIENT_CERTIFICATE": "false",
                "GOOGLE_API_USE_MTLS_ENDPOINT": "never",
            },
        }

        if args.mcp_server_url:
            deploy_config["env_vars"]["MCP_URL"] = args.mcp_server_url

        if args.env_var:
            for item in args.env_var:
                if "=" in item:
                    k, v = item.split("=", 1)
                    deploy_config["env_vars"][k.strip()] = v.strip()

        if args.data_bucket:
            deploy_config["env_vars"]["DATA_BUCKET"] = args.data_bucket

        if args.endpoint_url:
            deploy_config["env_vars"]["ENDPOINT_URL"] = args.endpoint_url

        if args.enable_telemetry:
            deploy_config["env_vars"]["GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY"] = "true"
            deploy_config["env_vars"]["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"] = "true"

        if args.enable_agent_identity:
            deploy_config["identity_type"] = "AGENT_IDENTITY"

        if args.allow_token_sharing:
            deploy_config["env_vars"]["GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES"] = "false"

        network_project = args.network_project or args.project

        if args.network_attachment:
            na_value = args.network_attachment
            if not na_value.startswith("projects/"):
                na_value = f"projects/{network_project}/regions/{args.region}/networkAttachments/{na_value}"
            deploy_config["psc_interface_config"] = {"network_attachment": na_value}

        if args.agent_gateway_egress or args.agent_gateway_ingress:
            deploy_config["agent_gateway_config"] = {}
            if args.agent_gateway_egress:
                deploy_config["agent_gateway_config"]["agent_to_anywhere_config"] = {
                    "agent_gateway": args.agent_gateway_egress
                }
            if args.agent_gateway_ingress:
                deploy_config["agent_gateway_config"]["client_to_agent_config"] = {
                    "agent_gateway": args.agent_gateway_ingress
                }

        # NATIVE SDK SCHEMA MATCH:
        # To support private DNS resolution of endpoints (like internal Cloud Run servers)
        # over PSC, DNS Peering must be configured inside the psc_interface_config.dns_peering_configs list.
        # Setting it as a root-level key (dns_peering_config) is rejected by the client-side PscInterfaceConfig validator.
        if args.target_network:
            domains = args.dns_domains.split(",") if args.dns_domains else ["run.app.", "foo.lab."]
            tn_value = args.target_network
            if not tn_value.startswith("projects/"):
                tn_value = f"projects/{network_project}/global/networks/{tn_value}"
                
            if "psc_interface_config" not in deploy_config:
                deploy_config["psc_interface_config"] = {}
                
            deploy_config["psc_interface_config"]["dns_peering_configs"] = [
                {
                    "domain": domain,
                    "target_project": network_project,
                    "target_network": tn_value,
                }
                for domain in domains
            ]

        if args.re_custom_sa:
            deploy_config["service_account"] = args.re_custom_sa

        print(f"Deploying agent '{args.display_name}'...")
        engine = client.agent_engines.create(agent=app, config=deploy_config)

    finally:
        os.chdir(original_cwd)
        shutil.rmtree(staging_dir, ignore_errors=True)

    reasoning_engine_name = engine.api_resource.name
    print(f"SUCCESS: Agent deployed: {reasoning_engine_name}")

    if args.ge_deploy:
        register_to_ge(
            project=args.project,
            app_id=args.app_id,
            agent_name=args.ge_auth_name,
            display_name=args.display_name,
            description=args.description,
            reasoning_engine_name=reasoning_engine_name,
            oauth_client_id=args.oauth_client_id,
            oauth_client_secret=args.oauth_client_secret,
        )


if __name__ == "__main__":
    main()
