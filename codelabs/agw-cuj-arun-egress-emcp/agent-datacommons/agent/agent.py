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

# Version 1.0.3

import os
import sys
from typing import Any, Dict, Optional

# Apply urllib3 PyOpenSSL workaround if available
try:
  import urllib3.contrib.pyopenssl
  urllib3.contrib.pyopenssl.extract_from_urllib3()
except Exception:
  pass

# Safely load environment variables from .env if present
try:
  from pathlib import Path
  from dotenv import load_dotenv
  for parent_level in [1, 2]:
    env_path = Path(__file__).parents[parent_level] / '.env'
    if env_path.exists():
      load_dotenv(dotenv_path=env_path, override=True)
      break
except Exception:
  pass

import google.auth
import google.auth.transport.requests
from google.adk.agents import LlmAgent
from google.adk.tools import McpToolset
from google.adk.tools.mcp_tool import StreamableHTTPConnectionParams


def get_auth_headers(context: Optional[Any] = None) -> Dict[str, str]:
  """Fetches API authentication headers to pass to Data Commons MCP server."""
  api_key = os.getenv('DC_API_KEY', '')
  if not api_key:
    print(
        '[HeaderProvider] Warning: DC_API_KEY not found in environment.',
        file=sys.stderr,
    )
  else:
    print('[HeaderProvider] DC_API_KEY loaded successfully.', file=sys.stderr)

  # Data Commons MCP public hosted server expects X-API-Key and Accepts event-stream
  return {
      'X-API-Key': api_key,
      'Accept': 'application/json, text/event-stream',
  }


# Define connection parameters for Data Commons MCP toolset
# Using the hosted public endpoint as documented by Data Commons
mcp_url = os.getenv('MCP_URL', 'https://api.datacommons.org/mcp')
connection_params = StreamableHTTPConnectionParams(url=mcp_url)

# Instantiate Data Commons MCP Toolset
datacommons_mcp_tools = McpToolset(
    connection_params=connection_params,
    header_provider=get_auth_headers,
)


# Define Standalone Root Agent utilizing Data Commons MCP tools
datacommons_agent = LlmAgent(
    name='agent_datacommons',
    model='gemini-2.5-flash',
    instruction=(
        'You are a Data Commons statistical and knowledge graph assistant. Your'
        ' purpose is to answer users\' queries about public statistics,'
        ' demographics, geographic data, health indicators, and economic'
        ' benchmarks by using your attached Data Commons MCP tools. Whenever'
        ' a user asks for statistics or factual information about places or'
        ' entities, use your Data Commons tools (such as search_indicators'
        ' and get_observations) to fetch accurate, up-to-date factual'
        ' data and provide clear, authoritative answers.'
    ),
    description='Standalone ADK agent utilizing 3P public Data Commons MCP tools.',
    tools=[datacommons_mcp_tools],
)

root_agent = datacommons_agent
