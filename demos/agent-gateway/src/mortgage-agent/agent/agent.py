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

"""ADK agent definition for the mortgage assistant with MCP tool connections."""

import logging
import os
from typing import Any

import httpx
from google.adk.agents.llm_agent import Agent
from google.adk.tools.base_tool import BaseTool
from google.adk.tools.tool_context import ToolContext

from . import tools

logger = logging.getLogger(__name__)

# Populated by _discover_mcp_toolsets at agent build time. Each entry mirrors
# what the registry returned plus the resolved tool_name_prefix, so the
# `list_mcp_connections` introspection tool can report what is actually wired
# up without re-querying the registry.
DISCOVERED_MCP_SERVERS: list[dict[str, Any]] = []

# Per-service prose, keyed by registry displayName. Entries here get rendered
# into the instruction's MCP services block alongside each service's live
# tool_name_prefix. Services discovered without a matching entry render with
# the prefix only — still functional, just less descriptive.
_SERVICE_DESCRIPTIONS: dict[str, str] = {
    "legacy-dms": (
        "the legacy document management system. Use to fetch tax returns, pay stubs, "
        "bank statements, and other applicant documents."
    ),
    "corporate-email": (
        "the corporate communications system. Use to read the corporate inbox. "
        "Write operations like sending emails may be restricted by the "
        "authorization gateway."
    ),
    "income-verification": (
        "a third-party income verification vendor. Use to verify reported income "
        "against employer records and tax filings."
    ),
}

# Template formatted at agent build time. The {mcp_services_doc} placeholder is
# filled from the live registry response so prefixes always match what ADK
# actually wired up — the LLM can't hallucinate a prefix it never sees.
_INSTRUCTION_TEMPLATE = """You are a mortgage underwriting assistant. You help loan officers process
mortgage applications by retrieving documents, verifying income, and communicating results.

You connect to backend systems through an Agent Gateway. The set of available tools is
discovered from the Agent Registry at startup and can change between deployments. Each
MCP service contributes tools with a service-specific prefix; only call tools whose
prefix appears in the list below.

**MCP services discovered from the registry:**
{mcp_services_doc}

**Workflow:**
1. Fetch the applicant's tax documents using the document management tools.
2. Verify the applicant's reported income using the income verification tools.
3. Compare the figures from both sources and note any discrepancies.
4. Summarize your findings clearly for the loan officer.

**Rules:**
- NEVER fabricate or estimate financial figures. Only report data returned by tools.
- Always cite which tool/system provided each piece of data.
- If a tool call fails or returns an error, report the error honestly to the user.
- Be concise and professional in all responses.
- When presenting tax return or applicant data, ALWAYS include the SSN field and display its value
exactly as returned by the tool (e.g. "[US_SOCIAL_SECURITY_NUMBER]"). Never omit SSN fields.

You also have utility tools:
- get_current_time: Returns the current time in any timezone.
- list_mcp_connections: Shows which MCP servers were discovered from the registry."""


def _render_mcp_services_doc() -> str:
    """Render the per-service block from the live DISCOVERED_MCP_SERVERS list."""
    if not DISCOVERED_MCP_SERVERS:
        return "_(no MCP services discovered — only utility tools are available)_"
    lines: list[str] = []
    for entry in DISCOVERED_MCP_SERVERS:
        prefix = entry.get("tool_name_prefix") or "(none)"
        name = entry.get("name") or entry.get("resource_name") or "?"
        desc = _SERVICE_DESCRIPTIONS.get(name)
        suffix = f" — connects to {desc}" if desc else ""
        lines.append(f"- **{name}** (tools prefixed `{prefix}_*`){suffix}")
    return "\n".join(lines)


def _find_http_status_error(exc: BaseException, status_code: int) -> bool:
    """Search exception chains and ExceptionGroups for an HTTPStatusError."""
    seen: set[int] = set()
    queue: list[BaseException] = [exc]
    while queue:
        current = queue.pop()
        if id(current) in seen:
            continue
        seen.add(id(current))
        if isinstance(current, httpx.HTTPStatusError) and current.response.status_code == status_code:
            return True
        if current.__cause__ is not None:
            queue.append(current.__cause__)
        if current.__context__ is not None:
            queue.append(current.__context__)
        if isinstance(current, BaseExceptionGroup):
            queue.extend(current.exceptions)
    return False


def _handle_tool_error(
    tool: BaseTool, args: dict[str, Any], tool_context: ToolContext, error: Exception
) -> dict | None:
    """Handle tool errors, returning a friendly message for 403 policy denials."""
    if _find_http_status_error(error, 403):
        logger.warning("Tool %s denied by authorization policy (403)", tool.name)
        return {
            "error": (
                f"The '{tool.name}' tool call was denied by the authorization "
                "gateway. This operation is not permitted by policy."
            ),
        }
    return None


def _discover_mcp_toolsets() -> list:
    """Discover MCP servers from the Agent Registry and return ADK toolsets.

    Project, location, and an optional server-name filter come from env vars
    set by deploy_agent.py:
      - MCP_REGISTRY_PROJECT  (falls back to GOOGLE_CLOUD_PROJECT)
      - MCP_REGISTRY_LOCATION (falls back to GOOGLE_CLOUD_LOCATION; rejected if "global")
      - MCP_REGISTRY_FILTER   (optional; passed through to list_mcp_servers as the
                               Google API list-filter expression)
      - MCP_REGISTRY_ENDPOINT (optional; full base URL override. When unset we
                               leave ADK's built-in default in place — currently
                               https://agentregistry.googleapis.com/v1alpha, the
                               only endpoint actually serving mcpServers today.
                               Set this to a regional URL once those endpoints
                               exist.)

    Discovery failures are logged and produce an empty list rather than
    aborting agent startup, so the agent still boots (with utility tools only)
    if the registry is unreachable.
    """
    DISCOVERED_MCP_SERVERS.clear()

    project = os.environ.get("MCP_REGISTRY_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
    location = os.environ.get("MCP_REGISTRY_LOCATION")
    if not location:
        env_location = os.environ.get("GOOGLE_CLOUD_LOCATION")
        # GOOGLE_CLOUD_LOCATION may legitimately be "global" for the model
        # endpoint; the registry needs a real region.
        if env_location and env_location != "global":
            location = env_location

    if not project or not location:
        logger.warning(
            "MCP registry discovery skipped: project=%r location=%r "
            "(set MCP_REGISTRY_PROJECT and MCP_REGISTRY_LOCATION).",
            project,
            location,
        )
        return []

    filter_str = os.environ.get("MCP_REGISTRY_FILTER")
    endpoint = os.environ.get("MCP_REGISTRY_ENDPOINT")

    try:
        # Imported lazily so the agent module loads even when ADK's optional
        # dependency chain is not satisfied locally. The deployed image must
        # pin a2a-sdk in deploy_agent.py's requirements list, otherwise this
        # import fails with `No module named 'a2a'` and discovery is skipped.
        from google.adk.integrations import agent_registry as _ar_module
        from google.adk.integrations.agent_registry import AgentRegistry
    except ImportError as e:
        logger.warning(
            "MCP registry discovery skipped: ADK agent_registry import failed (%s). "
            "On a deployed agent this means the requirements list in deploy_agent.py "
            "is missing a transitive dep (typically a2a-sdk).",
            e,
        )
        return []

    try:
        if endpoint:
            # Override ADK's hardcoded module-level endpoint constant. Remove
            # this patch if ADK starts accepting an explicit endpoint argument.
            _ar_module.AGENT_REGISTRY_BASE_URL = endpoint

        registry = AgentRegistry(project_id=project, location=location)
        response = registry.list_mcp_servers(filter_str=filter_str)
    except Exception:
        effective_endpoint = endpoint or getattr(_ar_module, "AGENT_REGISTRY_BASE_URL", "<adk-default>")
        logger.exception(
            "Failed to list MCP servers from registry %s/%s (endpoint=%s)",
            project,
            location,
            effective_endpoint,
        )
        return []

    raw_servers = response.get("mcpServers", [])
    effective_endpoint = endpoint or getattr(_ar_module, "AGENT_REGISTRY_BASE_URL", "<adk-default>")
    logger.info(
        "Registry %s/%s returned %d mcpServer(s) (endpoint=%s, filter=%r)",
        project,
        location,
        len(raw_servers),
        effective_endpoint,
        filter_str,
    )
    for s in raw_servers:
        logger.info(
            "  registry entry: name=%s displayName=%r interfaces=%s tools=%s",
            s.get("name"),
            s.get("displayName"),
            [(i.get("protocolBinding"), i.get("url")) for i in s.get("interfaces", [])],
            [t.get("name") for t in s.get("tools", [])],
        )

    toolsets = []
    for server in raw_servers:
        name = server.get("name")
        if not name:
            continue
        try:
            toolset = registry.get_mcp_toolset(mcp_server_name=name)
        except Exception:
            logger.exception("Failed to build toolset for MCP server %s", name)
            continue
        # ADK's StreamableHTTPConnectionParams default is 5s, which is shorter
        # than a Cloud Run cold start when min_instance_count=0. Survive a
        # restart/scale-out even when an instance happens to be cold.
        conn_params = getattr(toolset, "_connection_params", None)
        if conn_params is not None and hasattr(conn_params, "timeout"):
            conn_params.timeout = 30.0
        resolved_url = getattr(conn_params, "url", None)
        logger.info(
            "  built toolset: server=%s displayName=%r prefix=%s resolved_url=%s",
            name,
            server.get("displayName"),
            getattr(toolset, "tool_name_prefix", None),
            resolved_url,
        )
        toolsets.append(toolset)
        DISCOVERED_MCP_SERVERS.append(
            {
                "name": server.get("displayName") or name,
                "resource_name": name,
                "tool_name_prefix": getattr(toolset, "tool_name_prefix", None),
                "resolved_url": resolved_url,
            }
        )

    if not toolsets:
        logger.warning(
            "MCP registry discovery returned no servers in %s/%s (filter=%r, endpoint=%s).",
            project,
            location,
            filter_str,
            effective_endpoint,
        )
    else:
        logger.info(
            "Discovered %d MCP server(s) from registry %s/%s via %s",
            len(toolsets),
            project,
            location,
            effective_endpoint,
        )

    return toolsets


class _PickleSafeAgent(Agent):
    """Agent that rebuilds with MCP tools when unpickled or deep-copied."""

    def __reduce__(self):
        return (_build_agent, ())

    def __deepcopy__(self, memo):
        return _build_agent()


def _build_agent():
    """Build the agent with utility tools plus discovered MCP toolsets.

    Called at import time for local dev, and at unpickle time on Agent Engine.
    """
    _tools: list = [
        tools.get_current_time,
        tools.list_mcp_connections,
    ]
    _tools.extend(_discover_mcp_toolsets())

    instruction = _INSTRUCTION_TEMPLATE.format(mcp_services_doc=_render_mcp_services_doc())

    return _PickleSafeAgent(
        model=os.environ.get("MODEL_NAME", "gemini-3.1-flash-lite-preview"),
        name="mortgage_assistant_agent",
        description=(
            "A mortgage underwriting assistant that connects to legacy document management, "
            "income verification, and corporate email systems through an Agent Gateway."
        ),
        instruction=instruction,
        tools=_tools,
        on_tool_error_callback=_handle_tool_error,
    )


root_agent = _build_agent()
