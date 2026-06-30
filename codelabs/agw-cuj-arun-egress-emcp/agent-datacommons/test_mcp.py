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

# Version 05

# /// script
# dependencies = [
#   "mcp",
#   "httpx",
# ]
# ///

import argparse
import asyncio
import json
import os
import sys
import base64
from urllib.parse import urlparse
from mcp import ClientSession
from mcp.client.sse import sse_client
import httpx


class DummyTool:
    def __init__(self, data):
        self.name = data.get("name")
        self.description = data.get("description")
        self.inputSchema = data.get("inputSchema", {})

    def model_dump(self, **kwargs):
        return {
            "name": self.name,
            "description": self.description,
            "inputSchema": self.inputSchema,
        }


class StatelessHTTPClient:
    """A portable, generic client for MCP servers that use stateless HTTP JSON-RPC."""
    def __init__(self, url: str, headers: dict):
        self.url = url
        self.headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if headers:
            self.headers.update(headers)
        self.client = httpx.AsyncClient()

    async def _post(self, method: str, params: dict = None):
        payload = {"jsonrpc": "2.0", "method": method, "id": 1}
        if params is not None:
            payload["params"] = params

        response = await self.client.post(
            self.url, headers=self.headers, json=payload, timeout=30.0
        )
        response.raise_for_status()

        # Support both standard JSON responses and Server-Sent Events (event-stream)
        # where JSON objects are prefixed with "data: ".
        text = response.text
        json_str = ""
        for line in text.splitlines():
            if line.startswith("data: "):
                json_str = line[6:]
                break
        if not json_str:
            json_str = text

        try:
            data = json.loads(json_str)
        except json.JSONDecodeError as e:
            raise Exception(f"Failed to parse JSON response: {text[:200]}") from e

        if "error" in data:
            raise Exception(f"RPC Error: {data['error']}")
        return data.get("result", {})

    async def list_tools(self):
        res = await self._post("tools/list")
        tools_list = res.get("tools", [])

        class ToolsResponse:
            tools = [DummyTool(t) for t in tools_list]

        return ToolsResponse()

    async def call_tool(self, name: str, arguments: dict = None):
        res = await self._post(
            "tools/call", {"name": name, "arguments": arguments or {}}
        )
        content = res.get("content", [])

        class DummyContent:
            def __init__(self, c):
                self.text = c.get("text", str(c))

        class ResultResponse:
            content = [DummyContent(c) for c in content]

        return ResultResponse()


def generate_sample_json(schema):
    """Generate a sample JSON object based on a JSON schema."""
    sample = {}
    properties = schema.get("properties", {})
    required = schema.get("required", [])

    for prop_name, prop_info in properties.items():
        if prop_name in required:
            prop_type = prop_info.get("type", "string")
            if prop_type == "string":
                sample[prop_name] = "example_string"
            elif prop_type == "number":
                sample[prop_name] = 0.0
            elif prop_type == "integer":
                sample[prop_name] = 0
            elif prop_type == "boolean":
                sample[prop_name] = True
            elif prop_type == "object":
                sample[prop_name] = {}
            elif prop_type == "array":
                sample[prop_name] = []
            else:
                sample[prop_name] = None
    return sample


async def run_session(session, args, log):
    # 1. List tools
    response = await session.list_tools()
    log(f"\nAvailable tools ({len(response.tools)}):")
    for tool in response.tools:
        log(f"- {tool.name}: {tool.description}")

    # 2. Output toolspec if requested
    if args.toolspec == "include":
        tools_data = []
        for tool in response.tools:
            try:
                tool_dict = tool.model_dump(exclude_none=True)
            except AttributeError:
                tool_dict = {
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema,
                }
            tools_data.append(tool_dict)

        output_file = "toolspec.json"
        # Wrap in "tools" key for registry compatibility
        output_data = {"tools": tools_data}
        with open(output_file, "w") as f:
            json.dump(output_data, f, indent=2)
        log(f"\n[SUCCESS] Wrote tool spec to {output_file}")

        # Generate and print example usage
        if response.tools:
            first_tool = response.tools[0]
            schema = getattr(first_tool, "inputSchema", {})
            sample_args = generate_sample_json(schema)
            sample_json = json.dumps(sample_args)
            if args.printarg:
                print(f"export TOOL_ARG='{sample_json}'")
            else:
                log(f"\nRun this to set the arguments:")
                log(f"export TOOL_ARG='{sample_json}'")
                log(f"\nThen run:")
                log(
                    f'uv run test_mcp.py --toolcall=include --toolargs="$TOOL_ARG"'
                )

    # 3. Test calling a tool if requested
    if args.toolcall == "include" and response.tools:
        # Find the first tool with no required arguments
        target_tool = None
        for tool in response.tools:
            schema = getattr(tool, "inputSchema", {})
            if not schema.get("required"):
                target_tool = tool
                break

        # Fall back to the first tool if all require arguments
        if not target_tool:
            target_tool = response.tools[0]

        log(f"\nTesting tool call for: '{target_tool.name}'...")

        arguments = {}
        if args.toolargs:
            try:
                arguments = json.loads(args.toolargs)
            except json.JSONDecodeError as e:
                print(f"Error: --toolargs is not valid JSON: {e}")
                return

        try:
            result = await session.call_tool(
                target_tool.name, arguments=arguments
            )
            log(f"Result from server:")
            for item in result.content:
                log(getattr(item, "text", str(item)))
        except Exception as e:
            log(
                f"Called tool '{target_tool.name}', received response/error: {e}"
            )
            log("Note: If this tool requires arguments, an error is expected.")


def parse_headers_arg(headers_arg):
    headers = {}
    if not headers_arg:
        return headers
    try:
        headers = json.loads(headers_arg)
        if isinstance(headers, dict):
            return {str(k): str(v) for k, v in headers.items()}
    except json.JSONDecodeError:
        pass

    # Split by comma or newline
    for part in headers_arg.replace("\n", ",").split(","):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            k, v = part.split("=", 1)
            headers[k.strip()] = v.strip()
        elif ":" in part:
            k, v = part.split(":", 1)
            headers[k.strip()] = v.strip()
    return headers


async def main():
    parser = argparse.ArgumentParser(
        description="Universal MCP Server Testing and Toolspec Utility"
    )
    parser.add_argument(
        "--toolspec",
        choices=["include", "exclude"],
        default="exclude",
        help="Output a toolspec.json file in registry-compatible format.",
    )
    parser.add_argument(
        "--toolcall",
        choices=["include", "exclude"],
        default="exclude",
        help="Test calling a tool (prefers tools with no required arguments).",
    )
    parser.add_argument(
        "--toolargs",
        help="JSON string of arguments to pass to the tool call.",
    )
    parser.add_argument(
        "--printarg",
        action="store_true",
        help="Print only the export command for eval.",
    )
    parser.add_argument(
        "--transport",
        choices=["auto", "sse", "http"],
        default="auto",
        help="MCP transport to use ('sse' for standard Server-Sent Events, 'http' for stateless HTTP JSON-RPC).",
    )
    parser.add_argument(
        "--headers",
        help="Custom headers to pass to the MCP server (JSON string, or comma-separated Key=Value or Key:Value pairs).",
    )
    parser.add_argument(
        "--token",
        help="API key or token to pass in Authorization Bearer and X-API-Key headers.",
    )
    args = parser.parse_args()

    def log(msg, **kwargs):
        if args.printarg:
            print(msg, file=sys.stderr, **kwargs)
        else:
            print(msg, **kwargs)

    url = os.getenv("MCP_URL")
    if not url:
        log("Error: MCP_URL environment variable not set.")
        return

    # Hydrate headers from CLI or Environment
    headers = parse_headers_arg(args.headers)
    if not headers and os.getenv("MCP_HEADERS"):
        headers = parse_headers_arg(os.getenv("MCP_HEADERS"))

    # If no explicit credentials exist in headers, hydrate from --token flag or standard auth environment variables
    auth_keys_present = any(h.lower() in ["authorization", "x-api-key"] for h in headers)
    if not auth_keys_present:
        token = (
            args.token
            or os.getenv("API_KEY")
            or os.getenv("ID_TOKEN")
            or os.getenv("MCP_TOKEN")
        )
        if token:
            headers["X-API-Key"] = token
            headers["Authorization"] = f"Bearer {token}"

    log(f"Connecting to MCP server at: {url}")
    if headers:
        secure_headers_log = {k: "..." if "key" in k.lower() or "auth" in k.lower() or "token" in k.lower() else v for k, v in headers.items()}
        log(f"Using headers: {secure_headers_log}")

    transport = args.transport
    if transport == "auto":
        # Smart Auto-detection
        if url.rstrip("/").endswith("/sse"):
            log("[Auto-Detect] URL ends with /sse. Selecting SSE transport.")
            transport = "sse"
        else:
            log("[Auto-Detect] Probing URL for stateless HTTP JSON-RPC...")
            probe = StatelessHTTPClient(url, headers)
            try:
                await probe.list_tools()
                log("[Auto-Detect] Stateless HTTP JSON-RPC probe successful!")
                transport = "http"
            except Exception as e:
                log(f"[Auto-Detect] Stateless HTTP probe failed ({e}). Selecting SSE transport.")
                transport = "sse"

    if transport == "http":
        log("Using Stateless HTTP JSON-RPC transport.")
        client = StatelessHTTPClient(url, headers)
        await run_session(client, args, log)
    else:
        log("Using Server-Sent Events (SSE) transport.")
        if not url.endswith("/sse"):
            url = url.rstrip("/") + "/sse"

        async with sse_client(url, headers=headers) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                log("SSE Session initialized successfully!")
                await run_session(session, args, log)


if __name__ == "__main__":
    asyncio.run(main())
