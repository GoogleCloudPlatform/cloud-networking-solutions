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

"""Root agent definition for the software-bug-agent."""

import os

from google.adk.agents import Agent

from .prompt import agent_instruction
from .tools.tools import get_current_date, mcp_tools, search_tool

_model = os.environ.get("MODEL_NAME", "gemini-2.5-flash")

_tools = [get_current_date, search_tool]
if mcp_tools is not None:
    _tools.append(mcp_tools)

root_agent = Agent(
    model=_model,
    name="software_bug_agent",
    instruction=agent_instruction,
    tools=_tools,
)
