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

"""Bug Tickets MCP Server.

A minimal public, no-auth MCP server that serves an in-memory bug-ticket
dataset for the QuantumRoast coffee machine company. This replicates a
"public MCP endpoint" for the CUJ2 demo: the agent reaches it via the Agent
Gateway → SWP → Cloud NAT path, so the server's Cloud Run request logs show
the static NAT IP as the source address.

Serves three tools:
  list_tickets        — returns all tickets (with optional status/priority filter)
  get_ticket          — returns a single ticket by ID
  search_tickets      — full-text search across title + description

Transport: streamable-HTTP (fastmcp 3.x), matching what MCPToolset +
StreamableHTTPConnectionParams expects. Mount point: /mcp (default)
"""

from __future__ import annotations

import os
import re
from typing import Any

from fastmcp import FastMCP

# ---------------------------------------------------------------------------
# In-memory dataset
# ---------------------------------------------------------------------------

_TICKETS: list[dict[str, Any]] = [
    {
        "id": "QR-001",
        "title": "Grinder motor overheats after 10 minutes of operation",
        "description": "The grinder motor on the QR-3000 model reaches critical temperature after approximately 10 minutes of continuous operation, triggering the thermal cutoff. Customer reports this happens only when ambient temperature is above 28°C.",
        "status": "Open",
        "priority": "P1 - High",
        "assignee": "alice@quantumroast.example",
        "created_at": "2026-08-01T09:12:00Z",
        "updated_at": "2026-08-10T14:30:00Z",
        "tags": ["hardware", "grinder", "thermal"],
    },
    {
        "id": "QR-002",
        "title": "Firmware update 2.4.1 causes Wi-Fi connectivity loss",
        "description": "After applying firmware 2.4.1 via the companion app, the machine drops Wi-Fi connectivity and cannot be rediscovered. A factory reset restores connectivity but the firmware cannot be downgraded via the UI. Affects QR-5000 and QR-7000 models.",
        "status": "In Progress",
        "priority": "P0 - Critical",
        "assignee": "bob@quantumroast.example",
        "created_at": "2026-08-03T11:00:00Z",
        "updated_at": "2026-09-01T08:15:00Z",
        "tags": ["firmware", "wifi", "connectivity"],
    },
    {
        "id": "QR-003",
        "title": "Milk frother produces inconsistent foam density",
        "description": "The automatic milk frother on the QR-5000 produces micro-foam on first use each morning but coarse foam on subsequent uses without cleaning the steam wand. Suspected scale buildup on the thermoblock is limiting steam pressure.",
        "status": "Open",
        "priority": "P2 - Medium",
        "assignee": None,
        "created_at": "2026-08-05T16:45:00Z",
        "updated_at": "2026-08-05T16:45:00Z",
        "tags": ["hardware", "frother", "steam"],
    },
    {
        "id": "QR-004",
        "title": "App crashes on Android 15 when scheduling brew times",
        "description": "The companion Android app crashes (java.lang.NullPointerException in ScheduleActivity.onCreate) when trying to add a new scheduled brew time. Only reproducible on Android 15; Android 14 is unaffected. Stack trace attached in internal ticket.",
        "status": "Open",
        "priority": "P1 - High",
        "assignee": "carol@quantumroast.example",
        "created_at": "2026-08-07T09:00:00Z",
        "updated_at": "2026-08-20T10:00:00Z",
        "tags": ["android", "app", "crash", "scheduling"],
    },
    {
        "id": "QR-005",
        "title": "Water reservoir sensor false-positive 'low water' alerts",
        "description": "Several QR-3000 units report 'low water' alerts even when the reservoir is full. The float sensor appears to stick intermittently. A firmware workaround that polls the sensor twice before alerting was shipped in 2.3.8 but the issue still occurs on 2.4.0.",
        "status": "In Progress",
        "priority": "P2 - Medium",
        "assignee": "alice@quantumroast.example",
        "created_at": "2026-07-20T13:30:00Z",
        "updated_at": "2026-09-02T09:00:00Z",
        "tags": ["hardware", "sensor", "firmware", "water"],
    },
    {
        "id": "QR-006",
        "title": "OTA update fails silently when device time is not synced",
        "description": "If the machine's internal clock is not synchronized (e.g. after a long power outage), OTA updates from the companion app appear to succeed in the UI but the firmware version does not change. The update engine silently discards the package due to a certificate validity check that uses the local clock.",
        "status": "Open",
        "priority": "P1 - High",
        "assignee": "bob@quantumroast.example",
        "created_at": "2026-08-15T08:00:00Z",
        "updated_at": "2026-08-15T08:00:00Z",
        "tags": ["firmware", "ota", "clock", "tls"],
    },
    {
        "id": "QR-007",
        "title": "Shot volume inconsistency — portafilter basket calibration drift",
        "description": "Long-term testing shows that the QR-7000 under-extracts by 2–3 mL on shots taken after the first 50 uses of the day. Preliminary analysis suggests the flow-meter calibration drifts as the solenoid valve warms up. No customer-facing fix yet; internal investigation ongoing.",
        "status": "Open",
        "priority": "P3 - Low",
        "assignee": None,
        "created_at": "2026-07-01T10:00:00Z",
        "updated_at": "2026-08-28T11:00:00Z",
        "tags": ["hardware", "calibration", "flow-meter"],
    },
    {
        "id": "QR-008",
        "title": "iOS app does not request local network permission on iOS 18",
        "description": "The companion iOS app fails to discover machines via Bonjour on iOS 18 because the NSLocalNetworkUsageDescription key is missing from the Info.plist in version 3.1.0. The permission dialog never appears and the scan silently returns zero results.",
        "status": "Resolved",
        "priority": "P1 - High",
        "assignee": "carol@quantumroast.example",
        "created_at": "2026-06-10T14:00:00Z",
        "updated_at": "2026-07-05T09:30:00Z",
        "tags": ["ios", "app", "networking", "permissions"],
    },
]

# ---------------------------------------------------------------------------
# MCP server
# ---------------------------------------------------------------------------

mcp = FastMCP(
    name="bug-tickets-mcp",
    instructions="Bug ticket database for QuantumRoast coffee machines. Use list_tickets to browse, get_ticket to retrieve details by ID, and search_tickets for full-text search.",
)


@mcp.tool
def list_tickets(
    status: str | None = None,
    priority: str | None = None,
    assignee: str | None = None,
) -> list[dict[str, Any]]:
    """List all bug tickets, with optional filters.

    Args:
        status: Filter by status. One of: Open, In Progress, Resolved, Closed.
        priority: Filter by priority. One of: P0 - Critical, P1 - High, P2 - Medium, P3 - Low.
        assignee: Filter by assignee email (exact match).

    Returns:
        List of matching ticket objects.
    """
    results = list(_TICKETS)
    if status:
        results = [t for t in results if t["status"].lower() == status.lower()]
    if priority:
        results = [t for t in results if t["priority"].lower().startswith(priority.lower())]
    if assignee:
        results = [t for t in results if t.get("assignee") == assignee]
    return results


@mcp.tool
def get_ticket(ticket_id: str) -> dict[str, Any] | None:
    """Retrieve a single ticket by its ID (e.g. 'QR-001').

    Args:
        ticket_id: The ticket identifier (case-insensitive).

    Returns:
        The ticket object, or None if not found.
    """
    for ticket in _TICKETS:
        if ticket["id"].upper() == ticket_id.upper():
            return ticket
    return None


@mcp.tool
def search_tickets(query: str) -> list[dict[str, Any]]:
    """Search tickets by keyword across title, description, and tags.

    Args:
        query: Search string (case-insensitive). Multiple words are ANDed.

    Returns:
        List of tickets that match all query terms.
    """
    terms = [t.strip().lower() for t in re.split(r"\s+", query.strip()) if t.strip()]
    if not terms:
        return []

    results = []
    for ticket in _TICKETS:
        haystack = " ".join([
            ticket["title"],
            ticket["description"],
            " ".join(ticket.get("tags", [])),
            ticket.get("assignee") or "",
        ]).lower()
        if all(term in haystack for term in terms):
            results.append(ticket)
    return results


if __name__ == "__main__":
    # Cloud Run sets PORT; default to 8080.
    # Transport "http" uses streamable-HTTP (fastmcp 3.x default for HTTP).
    # The MCPToolset in the agent connects to <url>/mcp — FastMCP serves at /mcp by default.
    port = int(os.environ.get("PORT", 8080))
    mcp.run(transport="http", host="0.0.0.0", port=port)
