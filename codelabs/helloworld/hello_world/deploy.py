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

"""
Deploy the Hello World ADK agent to Google Agent Engine.

Usage:
    python deploy.py                        # deploy to prod
    python deploy.py --env dev              # deploy to dev
    python deploy.py --dry-run              # print the adk command without running it
    python deploy.py --update-id 123456     # update an existing deployment

Environment defaults are read from .env.{env} (e.g. .env.dev, .env.prod) if present,
falling back to static ENV_DEFAULTS.  Pass --project / --region / --gateway to override.

The deployed Agent Engine resource ID is cached in .deploy_state.json (git-ignored)
keyed by env so prod and dev IDs never collide.  Pass --update-id to force a specific
ID for that run (takes precedence over the state file).
"""

import argparse
import certifi
import json
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths and constants
# ---------------------------------------------------------------------------

REPO_ROOT  = Path(__file__).parent.resolve()
STATE_FILE = REPO_ROOT / ".deploy_state.json"

ENV_DEFAULTS: dict[str, dict] = {
    "prod": {
        "project": "prj-gemini-enterprise-500218",
        "region":  "us-central1",
        "gateway": "prd-uscentral1-gw",
    },
    "dev": {
        "project": "prj-gemini-enterprise-dev-218",
        "region":  "us-central1",
        "gateway": "dev-uscentral1-gw",
    },
}

AGENT_DIR          = "hello_world"
AGENT_DISPLAY_NAME = "Hello World Agent"
AGENT_DESCRIPTION  = "A minimal hello world ADK agent."

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_env_file(env: str) -> dict[str, str]:
    """Read deployment vars from .env.{env} (preferred) or .env (prod fallback only).

    Recognised keys:
        GOOGLE_CLOUD_PROJECT   → project
        GOOGLE_CLOUD_LOCATION  → region
        GOOGLE_CLOUD_GATEWAY   → gateway
    """
    env_specific = REPO_ROOT / f".env.{env}"
    legacy       = REPO_ROOT / ".env"

    if env_specific.exists():
        source = env_specific
    elif env == "prod" and legacy.exists():
        source = legacy
    else:
        return {}

    result: dict[str, str] = {}
    for raw in source.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key   = key.strip()
        value = value.strip().strip('"').strip("'")
        if key == "GOOGLE_CLOUD_PROJECT":
            result["project"] = value
        elif key == "GOOGLE_CLOUD_LOCATION":
            result["region"] = value
        elif key == "GOOGLE_CLOUD_GATEWAY":
            result["gateway"] = value
    return result


def _load_state() -> dict[str, str]:
    """Load cached Agent Engine resource IDs keyed by env."""
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def _save_state(state: dict[str, str]) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")
    print(f"  Saved deployment state → {STATE_FILE.name}")


def _find_adk() -> str:
    """Return the adk binary co-located with the running Python interpreter."""
    candidate = Path(sys.executable).parent / "adk"
    if candidate.exists():
        return str(candidate)
    return "adk"


def _extract_engine_id(text: str) -> str | None:
    """Parse a reasoningEngines/<ID> fragment from adk deploy output."""
    match = re.search(r"reasoningEngines/(\d+)", text)
    return match.group(1) if match else None


def ensure_ca_bundle(project: str, region: str, gateway: str, agent_dir: Path) -> None:
    """
    Extracts the Agent Gateway TLS Inspection CA and bundles it with certifi roots.
    Ensures zero-touch TLS inspection trust for Python aiohttp and requests.
    """
    bundle_path = agent_dir / "ca-bundle.crt"

    print(f"[*] Exporting Agent Gateway Root CA from {gateway}...")
    cmd = [
        "gcloud", "alpha", "network-services", "agent-gateways", "describe", gateway,
        f"--project={project}", f"--location={region}",
        "--format=json", "--quiet",
    ]
    raw_json = subprocess.check_output(cmd, text=True)
    gw_data = json.loads(raw_json)
    certs = (
        gw_data.get("agentGatewayCard", {}).get("rootCertificates")
        or gw_data.get("rootCertificates")
        or []
    )
    gateway_ca = "\n".join(c.strip() for c in certs if c.strip())
    if not gateway_ca:
        raise RuntimeError(f"Failed to extract rootCertificates from Agent Gateway '{gateway}'.")

    with open(certifi.where()) as f:
        public_roots = f.read()

    combined_bundle = (
        f"{public_roots}\n\n"
        f"# --- Google Cloud Agent Gateway TLS Inspection CA ---\n"
        f"{gateway_ca}\n"
    )
    bundle_path.write_text(combined_bundle)
    print(f"[✓] Generated {bundle_path} ({len(certs)} Gateway CA certificate(s) appended)")


def _write_agent_engine_config(env: str, project: str, region: str, gateway: str) -> None:
    """Write hello_world/.agent_engine_config.json and hello_world/.env before deploying.

    Builds from the unified ADK + Agent Gateway schema and stamps project, region,
    and gateway from resolved runtime values so CLI overrides take precedence.
    """
    agent_dir   = REPO_ROOT / AGENT_DIR
    config_path = agent_dir / ".agent_engine_config.json"

    gateway_resource = f"projects/{project}/locations/{region}/agentGateways/{gateway}"
    ca_bundle_container_path = f"/app/agents/{AGENT_DIR}/ca-bundle.crt"

    config = {
        "agent_gateway_config": {
            "agent_to_anywhere_config": {"agent_gateway": gateway_resource}
        },
        "identity_type": "AGENT_IDENTITY",
        "env_vars": {
            "SSL_CERT_FILE": ca_bundle_container_path,
            "REQUESTS_CA_BUNDLE": ca_bundle_container_path,
            "GRPC_DEFAULT_SSL_ROOTS_FILE_PATH": ca_bundle_container_path,
            "GOOGLE_CLOUD_DISABLE_DIRECT_PATH": "true",
            "GOOGLE_API_USE_MTLS": "never",
            "GOOGLE_API_USE_MTLS_ENDPOINT": "never",
            "GOOGLE_API_USE_CLIENT_CERTIFICATE": "false",
            "GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES": "false",
            "GOOGLE_CLOUD_PROJECT": project,
            "GOOGLE_CLOUD_LOCATION": region,
            "GOOGLE_GENAI_USE_VERTEXAI": "1",
            "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY": "true",
        },
    }

    config_path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"  Wrote .agent_engine_config.json ({env}) → {AGENT_DIR}/")

    # Also write to .env so ADK deploy preserves all variables when --otel_to_cloud is used
    env_path = agent_dir / ".env"
    env_lines = [f"{k}={v}" for k, v in config["env_vars"].items()]
    env_path.write_text("\n".join(env_lines) + "\n")
    print(f"  Wrote .env ({env}) → {AGENT_DIR}/")


def _build_command(project: str, region: str, engine_id: str | None, enable_otel: bool) -> list[str]:
    cmd = [
        _find_adk(),
        "deploy", "agent_engine",
        AGENT_DIR,
        "--project",      project,
        "--region",       region,
        "--display_name", AGENT_DISPLAY_NAME,
        "--description",  AGENT_DESCRIPTION,
    ]
    if enable_otel:
        cmd.append("--otel_to_cloud")
    if engine_id:
        cmd += ["--agent_engine_id", engine_id]
    return cmd


def _create_agent_identity_engine(project: str, region: str) -> str:
    """Create a lightweight Reasoning Engine with identity_type=AGENT_IDENTITY.

    Why this is required:
        When `adk deploy agent_engine` is called without `--agent_engine_id`, it calls
        `client.agent_engines.create()` with empty `config={}`. That provisions the
        Reasoning Engine with default `identity_type=SERVICE_ACCOUNT` (no SPIFFE SVID).
        Because `identity_type` cannot be switched from `SERVICE_ACCOUNT` to
        `AGENT_IDENTITY` during the subsequent `update()` call, outbound calls through
        an Agent Gateway fail authorization. Pre-creating the instance with
        `identity_type='AGENT_IDENTITY'` ensures SPIFFE Agent Identity is provisioned
        from day one.
    """
    import vertexai

    print("[*] Provisioning new Reasoning Engine with identity_type=AGENT_IDENTITY...")
    client = vertexai.Client(project=project, location=region)
    engine = client.agent_engines.create(
        config={
            "identity_type": "AGENT_IDENTITY",
            "display_name": AGENT_DISPLAY_NAME,
            "description": AGENT_DESCRIPTION,
        }
    )
    resource_name = engine.api_resource.name
    engine_id = resource_name.split("/")[-1]
    effective_id = getattr(engine.api_resource.spec, "effective_identity", None)
    print(f"[✓] Provisioned Reasoning Engine: {resource_name}")
    if effective_id:
        print(f"    SPIFFE Identity: {effective_id}")
    return engine_id


def _run_deploy(
    env: str,
    project: str,
    region: str,
    gateway: str,
    state: dict[str, str],
    force_id: str | None,
    dry_run: bool,
) -> bool:
    """Deploy the agent. Returns True on success."""
    agent_dir = REPO_ROOT / AGENT_DIR
    if not agent_dir.is_dir():
        print(f"\n[ERROR] Agent directory not found: {agent_dir}", file=sys.stderr)
        return False

    engine_id = force_id or state.get(env)
    action    = "Updating" if engine_id else "Creating"

    print()
    print("=" * 62)
    print(f"  {action}: {AGENT_DISPLAY_NAME}")
    print(f"  Environment     : {env}")
    if engine_id:
        print(f"  Agent Engine ID : {engine_id}")
    print(f"  Project         : {project}")
    print(f"  Region          : {region}")
    print(f"  Gateway         : {gateway}")
    print("=" * 62)

    ensure_ca_bundle(project, region, gateway, agent_dir)
    _write_agent_engine_config(env, project, region, gateway)

    if not engine_id and not dry_run:
        engine_id = _create_agent_identity_engine(project, region)
        state[env] = engine_id
        _save_state(state)

    cmd         = _build_command(project, region, engine_id, enable_otel=(env == "prod"))
    display_cmd = " ".join(f'"{tok}"' if " " in tok else tok for tok in cmd)
    print(f"\n  $ {display_cmd}\n")

    if dry_run:
        print("  [dry-run] Skipping execution.\n")
        return True

    # Stream output to terminal while also capturing to extract the resource ID.
    proc = subprocess.Popen(
        cmd,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    captured: list[str] = []
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        captured.append(line)
    proc.wait()

    full_output = "".join(captured)

    if proc.returncode != 0:
        print(f"\n[ERROR] Deployment failed (exit code {proc.returncode}).")
        return False

    # adk deploy agent_engine exits 0 even on failure — detect from output.
    if "Failed to deploy to Agent Platform" in full_output:
        print("\n[ERROR] Deployment failed (adk reported failure in output).")
        return False

    # Persist the Agent Engine ID so future runs update rather than recreate.
    if engine_id:
        state[env] = engine_id
        _save_state(state)
    else:
        new_id = _extract_engine_id(full_output)
        if new_id:
            state[env] = new_id
            _save_state(state)

    print(f"\n  Done: {AGENT_DISPLAY_NAME}")
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--env",
        choices=["prod", "dev"],
        default="prod",
        help="Target environment (default: prod).",
    )
    parser.add_argument(
        "--project",
        default=None,
        help="GCP project ID override.",
    )
    parser.add_argument(
        "--region",
        default=None,
        help="GCP region override.",
    )
    parser.add_argument(
        "--gateway",
        default=None,
        help="Agent Gateway resource name override (e.g. prd-uscentral1-gw).",
    )
    parser.add_argument(
        "--update-id",
        metavar="AGENT_ENGINE_ID",
        help="Existing Agent Engine resource ID to update instead of creating a new instance.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the adk command that would run without executing it.",
    )
    return parser


def _preflight_check() -> bool:
    try:
        import vertexai  # noqa: F401
        return True
    except ModuleNotFoundError:
        print(
            "[ERROR] 'vertexai' is not installed. It is required by 'adk deploy agent_engine'.\n"
            "Install it with:\n\n"
            "    pip install -r requirements.txt\n",
            file=sys.stderr,
        )
        return False


def main() -> int:
    parser = _build_parser()
    args   = parser.parse_args()

    if not _preflight_check():
        return 1

    # Resolve config: CLI args > .env.{env} file > static ENV_DEFAULTS.
    env_file_vals = _load_env_file(args.env)
    static        = ENV_DEFAULTS[args.env]

    project = args.project or env_file_vals.get("project") or static["project"]
    region  = args.region  or env_file_vals.get("region")  or static["region"]
    gateway = args.gateway or env_file_vals.get("gateway") or static["gateway"]

    print(f"\nDeploying to project '{project}' in '{region}' [env={args.env}]")
    if args.dry_run:
        print("DRY RUN — no changes will be made.")

    state = _load_state()
    ok    = _run_deploy(
        env=args.env,
        project=project,
        region=region,
        gateway=gateway,
        state=state,
        force_id=args.update_id,
        dry_run=args.dry_run,
    )

    print()
    if not ok:
        print("Deployment FAILED.")
        return 1

    if not args.dry_run:
        print(f"Successfully deployed: {AGENT_DISPLAY_NAME}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
