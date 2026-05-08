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

"""Tests for mortgage agent error handling logic."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import httpx

from agent import agent as agent_module
from agent.agent import (
    _discover_mcp_toolsets,
    _find_http_status_error,
    _handle_tool_error,
    _render_mcp_services_doc,
)


def _make_http_status_error(status_code: int) -> httpx.HTTPStatusError:
    response = MagicMock(spec=httpx.Response)
    response.status_code = status_code
    return httpx.HTTPStatusError("error", request=MagicMock(), response=response)


class TestFindHttpStatusError:
    def test_direct_match(self):
        exc = _make_http_status_error(403)
        assert _find_http_status_error(exc, 403) is True

    def test_wrong_status_code(self):
        exc = _make_http_status_error(500)
        assert _find_http_status_error(exc, 403) is False

    def test_chained_via_cause(self):
        inner = _make_http_status_error(403)
        outer = RuntimeError("wrapper")
        outer.__cause__ = inner
        assert _find_http_status_error(outer, 403) is True

    def test_chained_via_context(self):
        inner = _make_http_status_error(403)
        outer = RuntimeError("wrapper")
        outer.__context__ = inner
        assert _find_http_status_error(outer, 403) is True

    def test_exception_group(self):
        inner = _make_http_status_error(403)
        group = BaseExceptionGroup("group", [RuntimeError("other"), inner])
        assert _find_http_status_error(group, 403) is True

    def test_no_match(self):
        exc = RuntimeError("unrelated")
        assert _find_http_status_error(exc, 403) is False

    def test_nested_exception_group(self):
        inner = _make_http_status_error(403)
        inner_group = BaseExceptionGroup("inner", [inner])
        outer_group = BaseExceptionGroup("outer", [inner_group])
        assert _find_http_status_error(outer_group, 403) is True


class TestHandleToolError:
    def test_403_returns_friendly_message(self):
        tool = MagicMock()
        tool.name = "send_email"
        error = _make_http_status_error(403)
        result = _handle_tool_error(tool, {}, MagicMock(), error)
        assert result is not None
        assert "denied" in result["error"]
        assert "send_email" in result["error"]

    def test_non_403_returns_none(self):
        tool = MagicMock()
        tool.name = "read_email"
        error = _make_http_status_error(500)
        result = _handle_tool_error(tool, {}, MagicMock(), error)
        assert result is None

    def test_non_http_error_returns_none(self):
        tool = MagicMock()
        tool.name = "read_email"
        error = RuntimeError("something broke")
        result = _handle_tool_error(tool, {}, MagicMock(), error)
        assert result is None


class TestInstructionRendering:
    """The instruction must reflect the live registry prefixes, not hardcoded ones."""

    _DISCOVERED = [
        {"name": "legacy-dms", "tool_name_prefix": "legacy_dms"},
        {"name": "corporate-email", "tool_name_prefix": "corporate_email"},
        {"name": "income-verification", "tool_name_prefix": "income_verification"},
    ]

    def test_render_includes_live_prefixes_and_descriptions(self):
        with patch.object(agent_module, "DISCOVERED_MCP_SERVERS", self._DISCOVERED):
            doc = _render_mcp_services_doc()
        assert "`legacy_dms_*`" in doc
        assert "`corporate_email_*`" in doc
        assert "`income_verification_*`" in doc
        # Descriptions for known services come through.
        assert "legacy document management system" in doc
        assert "corporate communications system" in doc
        assert "third-party income verification vendor" in doc

    def test_render_handles_empty_discovery(self):
        with patch.object(agent_module, "DISCOVERED_MCP_SERVERS", []):
            doc = _render_mcp_services_doc()
        assert "no MCP services discovered" in doc

    def test_render_handles_unknown_service(self):
        with patch.object(
            agent_module,
            "DISCOVERED_MCP_SERVERS",
            [{"name": "future-service", "tool_name_prefix": "future_service"}],
        ):
            doc = _render_mcp_services_doc()
        assert "**future-service** (tools prefixed `future_service_*`)" in doc
        # No description prose appended for unknown services.
        assert "connects to" not in doc

    def test_built_agent_instruction_contains_live_prefixes(self):
        with (
            patch.object(agent_module, "_discover_mcp_toolsets", return_value=[]),
            patch.object(agent_module, "DISCOVERED_MCP_SERVERS", self._DISCOVERED),
        ):
            built = agent_module._build_agent()
        instruction = built.instruction
        # New prefixes present.
        assert "`legacy_dms_*`" in instruction
        assert "`corporate_email_*`" in instruction
        assert "`income_verification_*`" in instruction
        # Stale hardcoded prefixes are gone.
        assert "`dms_*`" not in instruction
        assert "`email_*`" not in instruction
        assert "`income_*`" not in instruction


class TestConnectionTimeoutOverride:
    """ADK's 5s default trips on Cloud Run cold starts; we override it to 30s."""

    def test_discover_overrides_toolset_timeout(self, monkeypatch):
        monkeypatch.setenv("MCP_REGISTRY_PROJECT", "test-project")
        monkeypatch.setenv("MCP_REGISTRY_LOCATION", "us-central1")
        monkeypatch.delenv("MCP_REGISTRY_FILTER", raising=False)
        monkeypatch.delenv("MCP_REGISTRY_ENDPOINT", raising=False)

        # Connection params object whose timeout we expect to be mutated.
        conn_params = MagicMock()
        conn_params.timeout = 5.0
        conn_params.url = "https://x.example/mcp"

        toolset = MagicMock()
        toolset._connection_params = conn_params
        toolset.tool_name_prefix = "x"

        registry_instance = MagicMock()
        registry_instance.list_mcp_servers.return_value = {
            "mcpServers": [{"name": "projects/p/locations/l/mcpServers/x", "displayName": "x"}]
        }
        registry_instance.get_mcp_toolset.return_value = toolset

        with patch(
            "google.adk.integrations.agent_registry.AgentRegistry",
            return_value=registry_instance,
        ):
            result = _discover_mcp_toolsets()

        assert result == [toolset]
        assert conn_params.timeout == 30.0
