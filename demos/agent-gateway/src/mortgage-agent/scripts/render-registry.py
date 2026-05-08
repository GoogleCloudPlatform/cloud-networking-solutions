#!/usr/bin/env python3
# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Render agent_config.yaml from agent_registry.yaml entries."""

import json
import sys
from pathlib import Path

import yaml

REGISTRY_YAML = Path("/workspace/config/agent_registry.yaml")
OUT_YAML = Path("/workspace/config/agent_config.yaml")


def load_registry() -> dict:
    """Load and parse the agent registry YAML."""
    if not REGISTRY_YAML.exists():
        print(f"ERROR: Registry not found at {REGISTRY_YAML}", file=sys.stderr)
        sys.exit(1)
    return yaml.safe_load(REGISTRY_YAML.read_text())


def extract_mcp_tool_prefixes(registry: dict) -> list[str]:
    """Extract mcp_tool_prefix from all MCP server entries."""
    prefixes = []
    for entry in registry.get("mcp_servers", []):
        if prefix := entry.get("mcp_tool_prefix"):
            prefixes.append(prefix)
    return prefixes


def render_agent_config(prefixes: list[str]) -> dict:
    """Render the agent_config.yaml structure with MCP tool prefixes."""
    return {
        "agent_config": {
            "tools": [{"name": prefix, "builtin": True} for prefix in prefixes]
        }
    }


def main():
    """Main entry point: load registry, extract prefixes, render config."""
    registry = load_registry()
    prefixes = extract_mcp_tool_prefixes(registry)

    if not prefixes:
        print("WARNING: No mcp_tool_prefix entries found in registry", file=sys.stderr)

    config = render_agent_config(prefixes)

    OUT_YAML.parent.mkdir(parents=True, exist_ok=True)
    OUT_YAML.write_text(yaml.dump(config, sort_keys=False))

    print(f"Rendered {len(prefixes)} MCP tool prefixes to {OUT_YAML}", file=sys.stderr)
    print(json.dumps(config, indent=2))


if __name__ == "__main__":
    main()
