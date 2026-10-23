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

"""Deploy the software-bug-agent to Vertex AI Agent Engine.

Two-phase workflow (mirrors demos/agent-gateway/src/mortgage-agent/deploy_agent.py):

  Phase 1 — build only (no engine created):
    python deploy_agent.py --project=PROJECT --region=REGION --build-only

    Packages and uploads the agent artifacts (pickle, dependencies, requirements)
    to the staging bucket and writes a manifest JSON. Terraform's
    google_vertex_ai_reasoning_engine then reads that manifest via package_spec.

  Phase 2 — deploy engine (Terraform):
    terraform apply -var deploy_reasoning_engine=true

    Terraform reads the manifest and creates the Reasoning Engine with
    agent_gateway_config bound to the Agent Gateway, so ALL egress from the
    engine flows through the VPC → SWP → Cloud NAT → static IP path.

Usage:
    # Build artifacts and write manifest (run this before terraform apply phase 2)
    python deploy_agent.py --project=my-project --region=us-central1 --build-only

    # Update an existing engine in-place (imperative path, optional)
    python deploy_agent.py --project=my-project --region=us-central1 \\
        --update=projects/PROJECT/locations/REGION/reasoningEngines/ENGINE_ID \\
        --agent-gateway=projects/PROJECT/locations/REGION/agentGateways/GATEWAY_ID

    # Override the MCP server URL (defaults to terraform output bug_tickets_mcp_url)
    python deploy_agent.py --project=my-project --region=us-central1 --build-only \\
        --mcp-url=https://bug-tickets-mcp-xxxx-uc.a.run.app/mcp
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile

# Load .env before reading any os.environ values so that local runs don't
# require manually exporting PROJECT_ID / BUG_TICKETS_MCP_URL etc.
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# See demos/agent-gateway/src/mortgage-agent/deploy_agent.py for the
# rationale: this overlay-venv script ensures the agent's dependencies
# layer OVER the base image rather than replacing its site-packages,
# preventing container startup crashes from transitive version drift.
_OVERLAY_VENV_SCRIPT = """\
#!/bin/bash
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

_OVERLAY_VENV_SCRIPT_PATH = "installation_scripts/create_venv.sh"


def _write_overlay_venv_script(staging_dir: str) -> None:
    script_path = os.path.join(staging_dir, _OVERLAY_VENV_SCRIPT_PATH)
    os.makedirs(os.path.dirname(script_path), exist_ok=True)
    with open(script_path, "w") as f:
        f.write(_OVERLAY_VENV_SCRIPT)
    os.chmod(script_path, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy software-bug-agent to Vertex AI Agent Engine"
    )
    parser.add_argument("--project", default=os.environ.get("PROJECT_ID"))
    parser.add_argument("--region", default=os.environ.get("REGION", "us-central1"))
    parser.add_argument("--staging-bucket", default=None)
    parser.add_argument("--display-name", default="Software Bug Triage Agent")
    parser.add_argument("--update", default=None, metavar="RESOURCE_NAME")
    parser.add_argument("--agent-gateway", default=None)
    parser.add_argument("--mcp-url", default=os.environ.get("BUG_TICKETS_MCP_URL"))
    parser.add_argument("--model", default="gemini-2.5-flash")
    parser.add_argument("--model-endpoint-location", default="us-central1")
    parser.add_argument(
        "--build-only",
        action="store_true",
        help="Package and upload artifacts; write manifest JSON. Do NOT create/update an engine.",
    )
    parser.add_argument("--artifacts-out", default=None)
    parser.add_argument("--gcs-dir", default="agent_engine")
    args = parser.parse_args()

    if not args.project:
        parser.error("--project is required (or set $PROJECT_ID)")

    staging_bucket = args.staging_bucket or f"gs://{args.project}-staging"

    agent_dir = os.path.dirname(os.path.abspath(__file__))
    if agent_dir not in sys.path:
        sys.path.insert(0, agent_dir)

    print("Deploying software-bug-agent to Agent Engine...")
    print(f"  Project:        {args.project}")
    print(f"  Region:         {args.region}")
    print(f"  Model:          {args.model}")
    print(f"  Staging bucket: {staging_bucket}")
    print(f"  Mode:           {'build-only (no engine)' if args.build_only else ('update' if args.update else 'create')}")
    if args.agent_gateway:
        print(f"  Agent Gateway:  {args.agent_gateway}")
    if args.mcp_url:
        print(f"  MCP URL:        {args.mcp_url}")
    print()

    os.environ["MODEL_NAME"] = args.model
    if args.mcp_url:
        os.environ["BUG_TICKETS_MCP_URL"] = args.mcp_url

    import vertexai

    vertexai.init(project=args.project, location=args.region, staging_bucket=staging_bucket)

    client = vertexai.Client(
        project=args.project,
        location=args.region,
        http_options=dict(api_version="v1beta1"),
    )

    from software_bug_agent.agent import root_agent
    from software_bug_agent.safe_adk import SafeAdkApp
    app = SafeAdkApp(agent=root_agent)

    description = "Software bug-triage agent for QuantumRoast — demonstrates public-internet egress via SWP + Cloud NAT with static IP (CUJ2)."

    deploy_config = dict(
        staging_bucket=staging_bucket,
        requirements=[
            "google-cloud-aiplatform[agent_engines]>=1.149.0,<1.154.0",
            "google-adk[a2a,agent-identity]==1.34.0",
            "google-auth>=2.0",
            "cloudpickle",
            "pydantic",
            "opentelemetry-instrumentation-google-genai",
            "opentelemetry-exporter-gcp-logging",
            # Transitive pins — see deploy_agent.py in demos/agent-gateway for rationale
            "aiohttp==3.14.1",
            "grpcio==1.82.1",
            "grpcio-status==1.81.1",
            "mcp==1.28.1",
            "opentelemetry-resourcedetector-gcp==1.12.0a0",
            "sse-starlette==3.4.5",
            "wrapt==1.17.3",
            "yarl==1.24.2",
        ],
        extra_packages=["software_bug_agent", _OVERLAY_VENV_SCRIPT_PATH],
        build_options={"installation_scripts": [_OVERLAY_VENV_SCRIPT_PATH]},
        env_vars={
            "ADK_ENABLE_MCP_GRACEFUL_ERROR_HANDLING": "true",
            "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY": "true",
            "GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES": "false",
            "GOOGLE_API_USE_CLIENT_CERTIFICATE": "false",
            "GOOGLE_API_USE_MTLS_ENDPOINT": "never",
            "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT": "true",
            "OTEL_TRACES_SAMPLER": "parentbased_traceidratio",
            "OTEL_TRACES_SAMPLER_ARG": "1.0",
            "GOOGLE_GENAI_USE_VERTEXAI": "True",
            "GOOGLE_CLOUD_LOCATION": args.model_endpoint_location,
            "MODEL_NAME": args.model,
            "GRPC_DNS_RESOLVER": "native",
            "GRPC_ENABLE_IPV6": "false",
            **({"BUG_TICKETS_MCP_URL": args.mcp_url} if args.mcp_url else {}),
        },
        display_name=args.display_name,
        description=description,
        min_instances=1,
        resource_limits={"cpu": "2", "memory": "4Gi"},
    )

    if args.agent_gateway:
        deploy_config["agent_gateway_config"] = {
            "agent_to_anywhere_config": {"agent_gateway": args.agent_gateway}
        }

    agent_src = os.path.join(agent_dir, "software_bug_agent")
    staging_dir = tempfile.mkdtemp(prefix="agent_deploy_")
    original_cwd = os.getcwd()

    try:
        shutil.copytree(
            agent_src,
            os.path.join(staging_dir, "software_bug_agent"),
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"),
        )
        _write_overlay_venv_script(staging_dir)
        os.chdir(staging_dir)

        if args.build_only:
            import json as _json

            from vertexai._genai import _agent_engines_utils as _aeu

            print(f"Build-only: staging to {staging_bucket}/{args.gcs_dir}/ ...")
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
            artifact_bucket = _aeu._get_gcs_bucket(
                project=args.project,
                location=args.region,
                staging_bucket=staging_bucket,
            )
            artifact_digests = []
            for filename in (_aeu._BLOB_FILENAME, _aeu._EXTRA_PACKAGES_FILE, _aeu._REQUIREMENTS_FILE):
                blob = artifact_bucket.get_blob(f"{args.gcs_dir}/{filename}")
                if blob is None:
                    artifact_digests.append(f"{filename}:absent")
                else:
                    digest = blob.md5_hash or blob.crc32c or blob.generation
                    artifact_digests.append(f"{filename}:{digest}")
            artifact_hash = hashlib.sha256("|".join(artifact_digests).encode()).hexdigest()

            manifest = {
                "python_version": f"{sys.version_info.major}.{sys.version_info.minor}",
                "agent_framework": _aeu._get_agent_framework(agent_framework=None, agent=app),
                "gcs_dir": args.gcs_dir,
                "pickle_filename": _aeu._BLOB_FILENAME,
                "dependencies_filename": _aeu._EXTRA_PACKAGES_FILE,
                "requirements_filename": _aeu._REQUIREMENTS_FILE,
                "artifact_hash": artifact_hash,
                "class_methods": class_methods,
            }
            if args.artifacts_out:
                out_path = (
                    args.artifacts_out if os.path.isabs(args.artifacts_out)
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
        else:
            engine = client.agent_engines.create(agent=app, config=deploy_config)

    finally:
        os.chdir(original_cwd)
        shutil.rmtree(staging_dir, ignore_errors=True)

    reasoning_engine_name = engine.api_resource.name
    print()
    print(f"Agent {'updated' if args.update else 'deployed'}: {reasoning_engine_name}")
    if not args.update:
        print()
        print("Set the resource name in your terraform.tfvars:")
        print(f'  # deploy_reasoning_engine = true  (already creates it via terraform)')
        print()
        print("Or pass to agent-gateway for imperative update:")
        print(f"  --agent-gateway=<gateway_id> --update={reasoning_engine_name}")


if __name__ == "__main__":
    main()
