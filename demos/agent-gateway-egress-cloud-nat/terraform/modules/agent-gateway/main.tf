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



/**
 * Agent Gateway Module (CUJ2 — egress-only variant)
 *
 * Provisions a Google-managed Agent Gateway in AGENT_TO_ANYWHERE mode with a
 * PSC-Interface network attachment. The agent's Reasoning Engine binds to this
 * gateway so that ALL of its egress (to any host) travels through the customer
 * VPC, where policy-based routes steer it through the Secure Web Proxy before
 * exiting via Cloud NAT with the reserved static IP.
 *
 * IAP REQUEST_AUTHZ and Model Armor CONTENT_AUTHZ extensions are intentionally
 * omitted — CUJ2 is scoped to the egress path only. The MCP server is public
 * and unauthenticated (INGRESS_TRAFFIC_ALL Cloud Run), so there is no ingress
 * IAM gate to enforce. See demos/agent-gateway for the ingress-governance demo
 * that adds those extensions.
 *
 * DNS peering is also omitted — the MCP server is at a public *.run.app URL
 * that resolves via standard public DNS. No private zone peering is required.
 */

locals {
  registry_uri = "//agentregistry.googleapis.com/projects/${var.project_id}/locations/${var.region}"
}

# PSC-Interface network attachment in the dedicated co-location subnet. This is
# what the Agent Gateway egresses through to reach the customer VPC (and from
# there the MCP internal LB).
resource "google_compute_network_attachment" "agent_gateway_na" {
  project               = var.project_id
  name                  = "${var.name_prefix}-na"
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [var.agent_gateway_subnet_self_link]
}

# Allow the gateway tenant's PSC-I NIC (sourcing from the dedicated subnet) to
# reach the MCP internal LB on its front-end port.
resource "google_compute_firewall" "agent_gateway_psc_i" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-psc-i"
  network       = var.network_self_link
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.agent_gateway_subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.mcp_lb_target_port)]
  }
}

# The Agent Gateway itself. Google-managed, AGENT_TO_ANYWHERE.
resource "google_network_services_agent_gateway" "this" {
  project  = var.project_id
  name     = var.name_prefix
  location = var.region

  google_managed {
    governed_access_path = "AGENT_TO_ANYWHERE"
  }

  registries = [local.registry_uri]

  agent_connectivity_template = "projects/${var.project_number}/locations/us-central1/agentConnectivityTemplates/${google_network_services_agent_connectivity_template.gateway_template.agent_connectivity_template_id}"

  ## Commenting this since we are using agent_connectivity_template
  # network_config {
  #   egress {
  #     network_attachment = google_compute_network_attachment.agent_gateway_na.id
  #   }
  # }
}

resource "google_network_services_agent_connectivity_template" "gateway_template" {
  project  = var.project_id
  location = var.region
  agent_connectivity_template_id = "${var.name_prefix}-${var.region}-template"

  access_path = "AGENT_TO_ANYWHERE"

  egress_network_config {
    network_attachment = google_compute_network_attachment.agent_gateway_na.id
    vpc_egress = "ALL_TRAFFIC"
  }
}

# Allow the Agent Gateway and AuthzPolicy to stabilize before dependent resources
# reference the gateway ID (e.g. the reasoning engine's agent_gateway_config).
resource "time_sleep" "wait_for_gateway" {
  depends_on      = [google_network_services_agent_gateway.this]
  create_duration = "30s"
}
