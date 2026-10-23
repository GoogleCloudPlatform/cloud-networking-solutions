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

"""Tools for the software-bug-agent.

Three tools are wired up:
  - get_current_date: returns today's date as a string.
  - search_tool: Google Search via ADK's built-in google_search AgentTool.
  - mcp_tools: MCPToolset connecting to the bug-tickets-mcp Cloud Run service.

The MCP server URL is read from the BUG_TICKETS_MCP_URL environment variable,
which is injected into the Reasoning Engine container by the agent-engine
Terraform module (var.mcp_server_url → env BUG_TICKETS_MCP_URL). If not set,
the toolset is skipped and a warning is logged.
"""

from __future__ import annotations

import logging
import os
from datetime import date

from google.adk.agents import Agent
from google.adk.tools import AgentTool, google_search
from google.adk.tools.mcp_tool import MCPToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StreamableHTTPConnectionParams

logger = logging.getLogger(__name__)


def get_current_date() -> str:
    """Returns today's date in YYYY-MM-DD format."""
    return date.today().isoformat()


# Google Search — for looking up CVEs, vendor advisories, community reports
search_agent = Agent(
    model="gemini-2.5-flash",
    name="search_agent",
    instruction="You are a research assistant. Use Google Search to find external information about software bugs, CVEs, and vendor advisories as requested.",
    tools=[google_search],
)
search_tool = AgentTool(agent=search_agent)

# MCPToolset connecting to the bug-tickets-mcp Cloud Run service.
# BUG_TICKETS_MCP_URL is set by Terraform (var.mcp_server_url) to the Cloud
# Run *.run.app URL with /mcp suffix. When running locally, set it in .env.
_mcp_url = os.environ.get("BUG_TICKETS_MCP_URL")

if _mcp_url:
    mcp_tools: MCPToolset | None = MCPToolset(
        connection_params=StreamableHTTPConnectionParams(url=_mcp_url, timeout=30.0),
    )
    logger.info("MCPToolset connected to %s", _mcp_url)
else:
    mcp_tools = None
    logger.warning(
        "BUG_TICKETS_MCP_URL is not set — MCP tools unavailable. "
        "Set this env var to the bug-tickets-mcp Cloud Run URL + /mcp "
        "(e.g. https://bug-tickets-mcp-xxxx-uc.a.run.app/mcp)."
    )
