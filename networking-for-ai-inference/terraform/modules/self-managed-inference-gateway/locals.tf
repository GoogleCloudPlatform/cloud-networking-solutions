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
# CONSOLIDATED LOCAL VALUES
# ==============================================================================
#
# This file consolidates all local values for the Self Managed Inference Gateway module.
# Values are derived from object-based variables for clean, maintainable code.
#
# ==============================================================================

# ==============================================================================
# COMMON CONFIGURATION
# ==============================================================================

locals {
  # Common resource name prefix
  resource_prefix = var.name_prefix

  # Common labels for all resources
  common_labels = merge(
    var.labels,
    {
      module      = "self-managed-inference-gateway"
      managed_by  = "terraform"
      environment = "production"
    }
  )
}

# ==============================================================================
# LOAD BALANCER CONFIGURATION
# ==============================================================================

locals {
  # Internal load balancer only
  lb_scheme = "INTERNAL_MANAGED"
}

# ==============================================================================
# DOMAIN AND SSL CONFIGURATION
# ==============================================================================


# ==============================================================================
# FIREWALL RULE NAMES
# ==============================================================================

locals {
  firewall_health_checks_name = "${local.resource_prefix}-allow-health-checks"
  firewall_proxy_traffic_name = "${local.resource_prefix}-allow-proxy-traffic"
}

# ==============================================================================
# MODEL ARMOR CONFIGURATION
# ==============================================================================

locals {
  # Dynamic service_name using var.region (falls back to computed value)
  model_armor_service_name = coalesce(
    var.security.model_armor.service_name,
    "modelarmor.${var.region}.rep.googleapis.com"
  )

  # Full template resource name from project_id + region + template_id
  model_armor_template_name = "projects/${var.project_id}/locations/${var.region}/templates/${var.security.model_armor.template_id}"

  # Auto-generate JSON config from protected_models + template
  model_armor_auto_config = length(var.security.model_armor.protected_models) > 0 ? jsonencode([
    for model in var.security.model_armor.protected_models : {
      model                      = model
      model_response_template_id = local.model_armor_template_name
      user_prompt_template_id    = local.model_armor_template_name
    }
  ]) : null

  # Explicit config wins, then auto-generated, then null (disabled)
  model_armor_config = try(coalesce(var.security.model_armor.config, local.model_armor_auto_config), null)
}
