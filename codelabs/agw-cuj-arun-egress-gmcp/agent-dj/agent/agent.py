# Version History:
# v1.0.3: Update LLM agent instructions to use flexible/wildcard case-insensitive matching to handle "DJ " prefixes seamlessly.
# v1.0.2: Add case-insensitive name matching guidelines to LLM agent instructions to prevent BigQuery case-sensitive mismatches.
# v1.0.1: Workaround for PyOpenSSL conflict with urllib3 and OpenTelemetry in reasoning engine runtimes
# v1.0.0: Original baseline implementation.

import sys
import os

# 
try:
    import urllib3.contrib.pyopenssl
    urllib3.contrib.pyopenssl.extract_from_urllib3()
except Exception:
    pass
from typing import Any, Dict, Optional
import google.auth
import google.auth.transport.requests
from google.adk.agents import LlmAgent
from google.adk.tools import McpToolset
from google.adk.tools.mcp_tool import StreamableHTTPConnectionParams


def get_auth_headers(context: Optional[Any] = None) -> Dict[str, str]:
  """Dynamically fetches regional authentication Bearer tokens to pass to Google MCP servers."""
  print('[HeaderProvider] Refreshing Google credentials...', file=sys.stderr)
  try:
    credentials, project = google.auth.default(
        scopes=[
            'https://www.googleapis.com/auth/bigquery',
            'https://www.googleapis.com/auth/cloud-platform',
        ]
    )
    request = google.auth.transport.requests.Request()
    credentials.refresh(request)
    token = credentials.token

    # Ensure we route query billing to your active customer project, avoiding Google's internal tenant project
    target_project = os.getenv('GOOGLE_CLOUD_PROJECT') or ACTIVE_PROJECT_ID or project

    print(
        f'[HeaderProvider] Token refreshed for project {target_project}.',
        file=sys.stderr,
    )
    return {
        'Authorization': f'Bearer {token}',
        'x-goog-user-project': target_project,
    }
  except Exception as e:
    print(f'[HeaderProvider] Error fetching credentials: {e}', file=sys.stderr)
    return {}


# Resolve the active Google Cloud project ID dynamically at module level
try:
  _, default_project = google.auth.default()
except Exception:
  default_project = None
ACTIVE_PROJECT_ID = os.getenv('GOOGLE_CLOUD_PROJECT') or default_project

project_instruction = (
    f" The active Google Cloud project ID is `{ACTIVE_PROJECT_ID}`. Always qualify your queries using this project ID (e.g., `SELECT * FROM {ACTIVE_PROJECT_ID}.dj_ds.disk_jockeys`)."
    if ACTIVE_PROJECT_ID
    else " Query against the active project or the specific project ID supplied by the user."
)

# Define connection parameters for Google Managed BigQuery MCP toolset
connection_params = StreamableHTTPConnectionParams(
    url='https://bigquery.googleapis.com/mcp'
)

# Instanciate official Google BigQuery MCP Toolset
bigquery_mcp_tools = McpToolset(
    connection_params=connection_params,
    header_provider=get_auth_headers,
)



# Define Standalone DJ Root Agent utilizing BQ MCP tools
dj_root_agent = LlmAgent(
    name='dj_root_agent',
    model='gemini-2.5-flash',
    instruction=(
        'You are a dj (disc jockey) management assistant. Assist users querying'
        ' the BigQuery database using your tools. You MUST use the BigQuery'
        ' execute_sql or execute_sql_readonly tool to query the database.'
        ' Note that BigQuery string comparisons are case-sensitive by default, and name '
        ' fields in the database might contain prefixes like "DJ " (e.g., "DJ Cosmopup"). '
        ' Therefore, you should always perform flexible, case-insensitive name checks. '
        ' Instead of strict equality, prefer using case-insensitive wildcard/partial '
        ' matching (e.g., LOWER(name) LIKE CONCAT("%", LOWER(input_name), "%")) '
        ' or matching names both with and without the "DJ " prefix to ensure you find '
        ' the correct entries even if the user omits or adds the prefix.'
        + project_instruction
    ),
    description='Standalone ADK agent utilizing Google Managed BigQuery MCP tools.',
    tools=[bigquery_mcp_tools],
)

root_agent = dj_root_agent
