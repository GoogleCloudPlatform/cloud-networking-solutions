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

"""Unit tests for the bug-tickets MCP server tools."""

import pytest

from server import get_ticket, list_tickets, search_tickets


def test_list_tickets_all():
    tickets = list_tickets()
    assert len(tickets) == 8


def test_list_tickets_status_filter():
    open_tickets = list_tickets(status="Open")
    assert all(t["status"] == "Open" for t in open_tickets)
    assert len(open_tickets) > 0


def test_list_tickets_priority_filter():
    critical = list_tickets(priority="P0")
    assert len(critical) == 1
    assert critical[0]["id"] == "QR-002"


def test_list_tickets_assignee_filter():
    alice = list_tickets(assignee="alice@quantumroast.example")
    assert len(alice) == 2
    assert all(t["assignee"] == "alice@quantumroast.example" for t in alice)


def test_get_ticket_found():
    ticket = get_ticket("QR-001")
    assert ticket is not None
    assert ticket["id"] == "QR-001"
    assert "grinder" in ticket["title"].lower()


def test_get_ticket_case_insensitive():
    ticket = get_ticket("qr-001")
    assert ticket is not None
    assert ticket["id"] == "QR-001"


def test_get_ticket_not_found():
    assert get_ticket("QR-999") is None


def test_search_tickets_single_term():
    results = search_tickets("firmware")
    assert len(results) > 0
    for t in results:
        haystack = (t["title"] + t["description"] + " ".join(t.get("tags", []))).lower()
        assert "firmware" in haystack


def test_search_tickets_multi_term():
    results = search_tickets("grinder motor")
    assert len(results) >= 1
    assert results[0]["id"] == "QR-001"


def test_search_tickets_no_match():
    results = search_tickets("xyzzy_no_match_ever")
    assert results == []


def test_search_tickets_empty_query():
    results = search_tickets("")
    assert results == []
