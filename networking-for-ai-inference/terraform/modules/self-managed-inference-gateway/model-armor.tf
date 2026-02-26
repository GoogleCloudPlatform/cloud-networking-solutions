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
# MODEL ARMOR TRAFFIC EXTENSION
# ==============================================================================
#
# This file implements the Model Armor traffic extension for payload protection.
# It uses google_network_services_lb_traffic_extension to attach the Model Armor
# service to the regional Application Load Balancer forwarding rules.
#
# ==============================================================================

resource "google_network_services_lb_traffic_extension" "model_armor" {
  count = var.security.model_armor.enabled ? 1 : 0

  name        = "${local.resource_prefix}-model-armor-extension"
  project     = var.project_id
  location    = var.region
  description = "Model Armor extension for self managed inference gateway"

  # Must match the load balancing scheme of forwarding rules
  load_balancing_scheme = local.lb_scheme

  # Attach to regional forwarding rules from regional-load-balancer.tf
  forwarding_rules = compact([
    var.domain.enable_https ? google_compute_forwarding_rule.regional_https[0].self_link : null,
    google_compute_forwarding_rule.regional_http.self_link
  ])

  # Extension chain configuration
  extension_chains {
    name = "chain-security-model-armor"

    # Match condition for applying the extension
    match_condition {
      cel_expression = (length(var.security.model_armor.paths) > 0 || length(var.security.model_armor.models) > 0) ? join(" || ", concat(
        [for p in var.security.model_armor.paths : "request.path.startsWith('${p}')"],
        [for m in var.security.model_armor.models : "request.headers['X-Gateway-Model-Name'] == '${m}'"]
      )) : var.security.model_armor.match_expression
    }

    extensions {
      name = "extension-model-armor"

      # Model Armor service name
      service = local.model_armor_service_name

      timeout   = "5s"
      fail_open = false

      supported_events = [
        "REQUEST_HEADERS",
        "REQUEST_BODY",
        "REQUEST_TRAILERS",
        "RESPONSE_HEADERS",
        "RESPONSE_BODY",
        "RESPONSE_TRAILERS"
      ]

      # Metadata passing the Model Armor configuration
      metadata = {
        model_armor_settings = local.model_armor_config
      }
    }
  }

  labels = local.common_labels
}
