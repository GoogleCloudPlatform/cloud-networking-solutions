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
End-to-end validation script for an ADK Agent deployed on Vertex AI Agent Engine
behind an Agent Gateway in VPC-SC.
"""

import argparse
import json
import os
from pathlib import Path
import sys
import vertexai

STATE_FILE = Path(__file__).parent.resolve() / ".deploy_state.json"


def _get_cached_engine_id(env: str = "prod") -> str | None:
    if not STATE_FILE.exists():
        return None
    try:
        data = json.loads(STATE_FILE.read_text())
        return data.get(env)
    except Exception:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate an ADK Reasoning Engine deployment end-to-end."
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT"),
        help="GCP project ID (defaults to PROJECT_ID or GOOGLE_CLOUD_PROJECT env var).",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("REGION") or os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1"),
        help="GCP region (default: us-central1).",
    )
    parser.add_argument(
        "--env",
        default="prod",
        help="Environment key in .deploy_state.json (default: prod).",
    )
    parser.add_argument(
        "--engine-id",
        default=None,
        help="Reasoning Engine ID or full resource name. If omitted, reads from .deploy_state.json.",
    )
    parser.add_argument(
        "--prompt",
        default="Hello! Please confirm you are responding through the Agent Gateway.",
        help="Test prompt to send to the agent.",
    )
    args = parser.parse_args()

    engine_id = args.engine_id or _get_cached_engine_id(args.env)
    if not engine_id:
        print(
            "[ERROR] No --engine-id specified and no cached ID found in .deploy_state.json.",
            file=sys.stderr,
        )
        return 1

    resource_name = (
        engine_id
        if engine_id.startswith("projects/")
        else f"projects/{args.project}/locations/{args.region}/reasoningEngines/{engine_id}"
    )

    print(f"[*] Initializing Vertex AI Client (project={args.project}, region={args.region})...")
    client = vertexai.Client(project=args.project, location=args.region)
    engine = client.agent_engines.get(name=resource_name)
    print(f"[*] Connected to Reasoning Engine: {engine.api_resource.name}")
    print(f"[*] Sending prompt: '{args.prompt}'\n")

    received_text = []
    model_version = None

    for event in engine.stream_query(message=args.prompt, user_id="validation-user"):
        if isinstance(event, dict):
            if "error_code" in event:
                print(f"[ERROR] Runtime returned error event: {event}", file=sys.stderr)
                return 1
            model_version = event.get("model_version") or model_version
            content = event.get("content", {})
            for part in content.get("parts", []):
                if "text" in part:
                    received_text.append(part["text"])

    full_response = "".join(received_text).strip()
    if not full_response:
        print("[ERROR] No response text received from agent.", file=sys.stderr)
        return 1

    print(f"[✓] Received Model Response (model: {model_version}):")
    print("-" * 60)
    print(full_response)
    print("-" * 60)
    print("\n[✓] End-to-end query validation PASSED!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
