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
 * Managed natively via google_network_services_agent_gateway and
 * google_network_security_authz_policy, avoiding pre-GA alpha API limits.
 */

locals {
  registry_uri = "//agentregistry.googleapis.com/projects/${var.project_id}/locations/${var.region}"
}

# PSC-Interface network attachment in the dedicated Agent Gateway subnet.
# This is what the Agent Gateway egresses through to reach the customer VPC
# (and from there, the SWP, NAT, and the public internet).
resource "google_compute_network_attachment" "agent_gateway" {
  project               = var.project_id
  name                  = "${var.name}-na"
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [var.agent_gateway_subnet_self_link]
}

# Destroy-time drain gate for the network attachment above.
#
# Terraform tears these down in the right order — the gateway references the
# attachment, so the gateway is deleted first. The problem is that the Agent
# Gateway DELETE returns once the control-plane record is gone, while the
# tenant-side PSC-Interface endpoint is removed asynchronously a few minutes
# later. Terraform deletes the attachment inside that window and Compute
# rejects it:
#
#   Error 412: Network Attachment with connected endpoints cannot be deleted.
#
# This node holds the attachment's delete until connectionEndpoints is empty.
resource "terraform_data" "network_attachment_drain" {
  input = {
    project = var.project_id
    region  = var.region
    name    = google_compute_network_attachment.agent_gateway.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Waiting for all PSC endpoints to detach from ${self.input.name} before deleting the Network Attachment..."
      for i in $(seq 1 45); do
        endpoints=$(gcloud compute network-attachments describe "${self.input.name}" \
          --project "${self.input.project}" --region "${self.input.region}" \
          --format='value(connectionEndpoints)' 2>/dev/null || echo "error")
        if [ "$endpoints" != "error" ] && [ -z "$endpoints" ]; then
          echo "All PSC endpoints have detached successfully. Proceeding with Network Attachment deletion."
          exit 0
        fi
        echo "PSC endpoints still attached (attempt $i/45). Waiting 10s..."
        sleep 10
      done
      echo "Timeout waiting for PSC endpoints to detach; attempting delete anyway." >&2
    EOT
  }
}

# Allow the Agent Gateway tenant's PSC-I NIC (sourcing from the dedicated subnet)
# to reach the Secure Web Proxy gateway on ports 80 and 443.
resource "google_compute_firewall" "agent_gateway_psc_i" {
  project       = var.project_id
  name          = "${var.name}-allow-psc-i"
  network       = var.network_self_link
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.agent_gateway_subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# The Agent Gateway itself. Google-managed, AGENT_TO_ANYWHERE.
resource "google_network_services_agent_gateway" "this" {
  depends_on = [
    google_compute_network_attachment.agent_gateway,
    google_compute_firewall.agent_gateway_psc_i,
    terraform_data.network_attachment_drain
  ]

  project  = var.project_id
  name     = var.name
  location = var.region

  google_managed {
    governed_access_path = "AGENT_TO_ANYWHERE"
  }

  registries = [local.registry_uri]

  network_config {
    egress {
      network_attachment = google_compute_network_attachment.agent_gateway.id
    }
  }
}

# Allow the Agent Gateway to stabilize before attaching authz policies.
resource "time_sleep" "wait_for_gateway" {
  depends_on      = [google_network_services_agent_gateway.this]
  create_duration = "30s"
}

# Allow-all AuthzPolicy attached to the Agent Gateway.
# In AGENT_TO_ANYWHERE mode, the Agent Gateway acts as a default-deny L7 proxy.
# We permit traffic through to the customer VPC where Secure Web Proxy (SWP)
# and GatewaySecurityPolicy enforce L7 governance.
resource "google_network_security_authz_policy" "allow_all" {
  depends_on     = [time_sleep.wait_for_gateway]
  provider       = google-beta
  project        = var.project_id
  name           = "${var.name}-allow-all"
  location       = var.region
  policy_profile = "REQUEST_AUTHZ"
  action         = "ALLOW"

  target {
    resources = [google_network_services_agent_gateway.this.id]
  }

  http_rules {
    when = "true"
  }
}
