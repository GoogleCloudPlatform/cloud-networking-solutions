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
 * Provisions a Google-managed Agent Gateway in AGENT_TO_ANYWHERE mode with an
 * AgentConnectivityTemplate enforcing vpcEgress = ALL_TRAFFIC.
 *
 * The agent's Reasoning Engine binds to this gateway so that ALL of its egress
 * (including public Cloud Run MCP servers and external APIs) travels through
 * the customer VPC, where policy-based routes steer it through the Secure Web Proxy
 * before exiting via Cloud NAT with the reserved static IP.
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

# The Agent Gateway itself. Linked to the Agent Connectivity Template (ALL_TRAFFIC) via v1 REST API.
resource "terraform_data" "agent_gateway" {
  input = {
    project_id            = var.project_id
    project_number        = var.project_number
    region                = var.region
    agent_gateway_name    = var.name
    template_name         = var.template_name != null ? var.template_name : "${var.name}-template"
    network_attachment_id = google_compute_network_attachment.agent_gateway.id
    registry_uri          = local.registry_uri
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -e
      cd ..
      echo "Creating Agent Connectivity Template with ALL_TRAFFIC..."
      ./scripts/create_connectivity_template.sh "${self.input.project_id}" "${self.input.region}" "${self.input.template_name}" "${self.input.network_attachment_id}" "none"

      echo "Creating Agent Gateway via v1 REST API..."
      ./scripts/manage_agent_gateway.sh create "${self.input.project_id}" "${self.input.region}" "${self.input.agent_gateway_name}" "${self.input.template_name}" "${self.input.registry_uri}"

      echo "Creating allow-all AuthzPolicy YAML config..."
      cat <<EOF > config/agent-gateway-authz-policy.yaml
name: projects/${self.input.project_id}/locations/${self.input.region}/authzPolicies/${self.input.agent_gateway_name}-allow-all
action: ALLOW
policyProfile: REQUEST_AUTHZ
target:
  resources:
  - projects/${self.input.project_number}/locations/${self.input.region}/agentGateways/${self.input.agent_gateway_name}
httpRules:
- when: 'true'
EOF

      echo "Importing allow-all AuthzPolicy via gcloud..."
      gcloud network-security authz-policies import "${self.input.agent_gateway_name}-allow-all" \
        --source="config/agent-gateway-authz-policy.yaml" \
        --location="${self.input.region}" \
        --project="${self.input.project_id}"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Deleting AuthzPolicy..."
      gcloud network-security authz-policies delete "${self.input.agent_gateway_name}-allow-all" \
        --location="${self.input.region}" \
        --project="${self.input.project_id}" \
        --quiet || true

      echo "Resetting agent-gateway-authz-policy.yaml to placeholder template..."
      cat <<EOF > config/agent-gateway-authz-policy.yaml
name: projects/PROJECT_ID/locations/REGION/authzPolicies/agent-gateway-allow-all
action: ALLOW
policyProfile: REQUEST_AUTHZ
target:
  resources:
  - projects/PROJECT_NUMBER/locations/REGION/agentGateways/agent-gateway
httpRules:
- when: 'true'
EOF

      cd ..
      echo "Deleting Agent Gateway via v1 REST API..."
      ./scripts/manage_agent_gateway.sh delete "${self.input.project_id}" "${self.input.region}" "${self.input.agent_gateway_name}" || true

      echo "Deleting Agent Connectivity Template..."
      ./scripts/delete_connectivity_template.sh "${self.input.project_id}" "${self.input.region}" "${self.input.template_name}" || true
    EOT
  }

  depends_on = [
    google_compute_network_attachment.agent_gateway,
    google_compute_firewall.agent_gateway_psc_i,
    terraform_data.network_attachment_drain
  ]
}

# Allow the Agent Gateway and AuthzPolicy to stabilize before dependent resources
# reference the gateway ID (e.g. the reasoning engine's agent_gateway_config).
resource "time_sleep" "wait_for_gateway" {
  depends_on      = [terraform_data.agent_gateway]
  create_duration = "30s"
}
