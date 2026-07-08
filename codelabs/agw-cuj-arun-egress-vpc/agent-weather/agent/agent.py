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

# Version 1.0.2

import os
import sys
from typing import Any, Dict, Optional
from urllib.parse import urlparse

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
import google.auth.impersonated_credentials
import google.auth.transport.requests
import google.oauth2.id_token
from google.adk.agents import LlmAgent
from google.adk.tools import McpToolset
from google.adk.tools.mcp_tool import StreamableHTTPConnectionParams


def get_auth_headers(context: Optional[Any] = None) -> Dict[str, str]:
  """Fetches Google-signed OIDC ID token header for Cloud Run authentication.

  Supports Service Account Impersonation when Agent Identity (SPIFFE JWT-SVID)
  is enabled, bridging Agent Identity to Cloud Run's OIDC requirement.
  """
  mcp_url = os.getenv('MCP_URL', '')
  if not mcp_url or 'localhost' in mcp_url:
    return {}

  # Audience for Cloud Run is the base service URL (e.g. https://mcp-weather-xxx.run.app)
  parsed = urlparse(mcp_url)
  audience = f"{parsed.scheme}://{parsed.netloc}"
  invoker_sa = os.getenv('MCP_INVOKER_SA', '')

  print(f'[HeaderProvider] Diagnostics: mcp_url={mcp_url}, audience={audience}, invoker_sa={invoker_sa}', file=sys.stderr)

  try:
    auth_req = google.auth.transport.requests.Request()
    if invoker_sa:
      source_creds, source_project = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
      print(f'[HeaderProvider] source_creds type={type(source_creds).__name__}, source_project={source_project}', file=sys.stderr)

      target_sa_creds = google.auth.impersonated_credentials.Credentials(
          source_credentials=source_creds,
          target_principal=invoker_sa,
          target_scopes=['https://www.googleapis.com/auth/cloud-platform'],
          lifetime=3600,
      )
      id_creds = google.auth.impersonated_credentials.IDTokenCredentials(
          target_credentials=target_sa_creds,
          target_audience=audience,
          include_email=True,
      )
      id_creds.refresh(auth_req)
      token = id_creds.token
      print(f'[HeaderProvider] Impersonated OIDC token minted successfully (len={len(token) if token else 0})', file=sys.stderr)
    else:
      token = google.oauth2.id_token.fetch_id_token(auth_req, audience)
      print(f'[HeaderProvider] Standard OIDC token fetched successfully (len={len(token) if token else 0})', file=sys.stderr)

    return {'Authorization': f'Bearer {token}'}
  except Exception as e:
    print(f'[HeaderProvider] ERROR: Failed to fetch OIDC ID token: {e}', file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    return {}


# Define connection parameters for Weather MCP toolset
mcp_url = os.getenv('MCP_URL', 'http://localhost:8080/mcp')
connection_params = StreamableHTTPConnectionParams(url=mcp_url)

# Instantiate Weather MCP Toolset with OIDC authentication header provider
weather_mcp_tools = McpToolset(
    connection_params=connection_params,
    header_provider=get_auth_headers,
)

# Define Standalone Root Agent utilizing Weather MCP tools
weather_agent = LlmAgent(
    name='agent_weather',
    model='gemini-2.5-flash',
    instruction=(
        'You are a helpful weather assistant. Your purpose is to answer users\''
        ' queries about current weather conditions, temperatures, and wind speeds'
        ' for cities and locations worldwide using your attached Weather MCP tools.'
        ' Whenever a user asks for weather info, use your get_weather tool'
        ' to fetch accurate, real-time data and provide clear answers.'
    ),
    description='Standalone ADK agent utilizing custom Weather MCP tools hosted on Cloud Run.',
    tools=[weather_mcp_tools],
)

root_agent = weather_agent
