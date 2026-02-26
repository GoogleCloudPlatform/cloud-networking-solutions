/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

# ==============================================================================
# REGIONAL LB ROUTE EXTENSION FOR BODY-BASED ROUTING
# ==============================================================================
#
# This file implements Body-Based Routing using LbRouteExtension with the
# regional internal Application Load Balancer.
#
# Key difference from LbTrafficExtension:
# - Route extensions run BEFORE URL map routing decisions
# - Route extensions can request body processing via ext_proc mode_override
# - Headers injected by route extension ext_proc affect routing
#
# Architecture based on GKE Inference Gateway body-based routing:
# https://cloud.google.com/kubernetes-engine/docs/how-to/configure-body-based-routing
#
# Flow:
# 1. Request arrives at regional internal ALB
# 2. LbRouteExtension invokes ext_proc with REQUEST_HEADERS event
# 3. ext_proc uses mode_override to request REQUEST_BODY
# 4. ext_proc extracts model from JSON body, injects X-Gateway-Model-Name header
# 5. URL map evaluates routing rules with the injected header
# 6. Request is routed to appropriate backend (GKE, Vertex AI, etc.)
#
# ==============================================================================

# ==============================================================================
# LB ROUTE EXTENSION FOR BODY-BASED ROUTING
# ==============================================================================

resource "google_network_services_lb_route_extension" "bbr" {
  count = var.body_based_routing.enabled ? 1 : 0

  provider = google-beta

  name        = "${local.resource_prefix}-bbr-route-ext"
  project     = var.project_id
  location    = var.region
  description = "Body-Based Routing extension using mode_override for body access"

  # Internal load balancer scheme
  load_balancing_scheme = "INTERNAL_MANAGED"

  # Attach to regional forwarding rules
  # When HTTPS is enabled, HTTP only does redirects so we only attach to HTTPS
  # When HTTPS is disabled, we attach to HTTP
  forwarding_rules = compact([
    var.domain.enable_https ? google_compute_forwarding_rule.regional_https[0].self_link : null,
    var.domain.enable_https ? null : google_compute_forwarding_rule.regional_http.self_link
  ])

  # Extension chain configuration
  extension_chains {
    name = "body-based-routing-chain"

    match_condition {
      cel_expression = var.body_based_routing.match_expression
    }

    extensions {
      name      = "bbr-model-extractor"
      authority = var.domain.name
      service   = module.bbr_ext_proc[0].backend_service_self_link
      timeout   = "5s"

      supported_events = [
        "REQUEST_HEADERS",
        "REQUEST_BODY",
        "REQUEST_TRAILERS"
      ]

      request_body_send_mode = "BODY_SEND_MODE_FULL_DUPLEX_STREAMED"

      forward_headers = ["authorization", "content-type", "content-length"]
    }
  }

  labels = local.common_labels
}
