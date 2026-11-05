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

from __future__ import annotations

import logging
import os
import socket
import sys
import urllib.parse
from typing import Any, Optional

logger = logging.getLogger("software_bug_agent.safe_adk")
logger.setLevel(logging.DEBUG)

if sys.platform != "darwin":
    # Force IPv4 only — disable IPv6 to prevent [Errno 101] Network is unreachable in aiohttp / aiohappyeyeballs
    _original_getaddrinfo = socket.getaddrinfo

    def _custom_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
        if family == socket.AF_UNSPEC:
            family = socket.AF_INET
        elif family == socket.AF_INET6:
            raise socket.gaierror(socket.EAI_ADDRFAMILY, "Address family not supported")
        return _original_getaddrinfo(host, port, family, type, proto, flags)

    socket.getaddrinfo = _custom_getaddrinfo

try:
    from vertexai.agent_engines import AdkApp
except ImportError:
    from vertexai.preview.reasoning_engines import AdkApp  # type: ignore[no-redef]


def _diagnose_network() -> None:
    """Diagnose container environment, DNS, and proxy configuration."""
    print("=== [DIAGNOSTIC] Container Network & Environment Inspection ===")
    
    # 1. Inspect Proxy Environment Variables
    proxy_keys = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        "GRPC_PROXY", "grpc_proxy", "GOOGLE_API_USE_MTLS_ENDPOINT",
        "GOOGLE_API_USE_CLIENT_CERTIFICATE", "GRPC_DNS_RESOLVER",
        "BUG_TICKETS_MCP_URL"
    ]
    for k in proxy_keys:
        val = os.environ.get(k)
        if val is not None:
            print(f"[DIAGNOSTIC ENV] {k} = {val}")

    # 2. Inspect DNS Resolution
    targets = [
        "us-central1-aiplatform.googleapis.com",
        "telemetry.googleapis.com",
    ]
    mcp_url = os.environ.get("BUG_TICKETS_MCP_URL")
    if mcp_url:
        parsed = urllib.parse.urlparse(mcp_url)
        if parsed.hostname:
            targets.append(parsed.hostname)

    for target in targets:
        try:
            results = socket.getaddrinfo(target, 443, socket.AF_INET, socket.SOCK_STREAM)
            ips = [r[4][0] for r in results]
            print(f"[DIAGNOSTIC DNS] {target} -> {ips}")
        except Exception as e:
            print(f"[DIAGNOSTIC DNS ERROR] {target} -> {type(e).__name__}: {e}")

    # 3. Test Direct TCP Socket Connection to MCP Host
    if mcp_url:
        parsed = urllib.parse.urlparse(mcp_url)
        host = parsed.hostname
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        if host:
            try:
                s = socket.create_connection((host, port), timeout=5)
                s.close()
                print(f"[DIAGNOSTIC TCP] Successfully opened TCP socket to {host}:{port}")
            except Exception as e:
                print(f"[DIAGNOSTIC TCP ERROR] Failed to connect to {host}:{port}: {type(e).__name__}: {e}")

    print("=== [DIAGNOSTIC] End of Network Inspection ===")


class SafeAdkApp(AdkApp):
    """AdkApp subclass with diagnostic logging and safe session builders."""

    def __init__(self, **kwargs: Any) -> None:
        from google.adk.sessions.in_memory_session_service import InMemorySessionService
        from google.adk.memory.in_memory_memory_service import InMemoryMemoryService

        kwargs.setdefault("session_service_builder", InMemorySessionService)
        kwargs.setdefault("memory_service_builder", InMemoryMemoryService)
        super().__init__(**kwargs)

    def set_up(self) -> None:
        _diagnose_network()
        super().set_up()

    def project_id(self) -> Optional[str]:
        return (
            self._tmpl_attrs.get("project")
            or os.environ.get("GOOGLE_CLOUD_PROJECT")
        )

    async def async_stream_query(self, *, message, user_id, session_id=None, **kwargs):
        print(f"[DIAGNOSTIC QUERY] Starting async_stream_query. user_id={user_id}, session_id={session_id}")
        _diagnose_network()
        try:
            async for event in super().async_stream_query(
                message=message, user_id=user_id, session_id=session_id, **kwargs
            ):
                yield event
        except Exception as exc:
            print(f"[DIAGNOSTIC QUERY ERROR] Exception in async_stream_query: {type(exc).__name__}: {exc}")
            err_msg = str(exc).lower()
            if "session" not in err_msg or "not found" not in err_msg or session_id is None:
                raise
            print("[DIAGNOSTIC QUERY RETRY] Retrying without session_id...")
            async for event in super().async_stream_query(
                message=message, user_id=user_id, session_id=None, **kwargs
            ):
                yield event
