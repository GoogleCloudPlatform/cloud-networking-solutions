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
# LOAD BALANCER OUTPUTS
# ==============================================================================

output "gateway_ip" {
  description = "IP address of the self managed inference gateway (shared VIP for HTTP and HTTPS)"
  value       = google_compute_address.shared_vip.address
}

output "gateway_url" {
  description = "URL of the self managed inference gateway"
  value       = var.domain.enable_https ? "https://${var.domain.name}" : "http://${var.domain.name}"
}

output "url_map_id" {
  description = "ID of the regional URL map resource"
  value       = google_compute_region_url_map.regional_gateway.id
}

output "url_map_name" {
  description = "Name of the regional URL map resource"
  value       = google_compute_region_url_map.regional_gateway.name
}

output "http_proxy_id" {
  description = "ID of the regional HTTP target proxy"
  value       = google_compute_region_target_http_proxy.regional_gateway.id
}

output "https_proxy_id" {
  description = "ID of the regional HTTPS target proxy (if HTTPS is enabled)"
  value       = var.domain.enable_https ? google_compute_region_target_https_proxy.regional_gateway[0].id : null
}

output "forwarding_rule_http_id" {
  description = "ID of the regional HTTP forwarding rule"
  value       = google_compute_forwarding_rule.regional_http.id
}

output "forwarding_rule_https_id" {
  description = "ID of the regional HTTPS forwarding rule (if HTTPS is enabled)"
  value       = var.domain.enable_https ? google_compute_forwarding_rule.regional_https[0].id : null
}

output "forwarding_rule_http_self_link" {
  description = "Self link of the regional HTTP forwarding rule"
  value       = google_compute_forwarding_rule.regional_http.self_link
}

output "forwarding_rule_https_self_link" {
  description = "Self link of the regional HTTPS forwarding rule (if HTTPS is enabled)"
  value       = var.domain.enable_https ? google_compute_forwarding_rule.regional_https[0].self_link : null
}

# ==============================================================================
# BACKEND SERVICE OUTPUTS
# ==============================================================================

output "backend_ids" {
  description = "Map of backend names to their IDs"
  value       = local.backend_ids
}

output "default_backend_id" {
  description = "ID of the default backend service"
  value       = local.default_backend_id
}

output "backend_services" {
  description = "Map of backend service resources"
  value = {
    for k, v in google_compute_region_backend_service.backends : k => {
      id        = v.id
      self_link = v.self_link
      name      = v.name
    }
  }
}

# ==============================================================================
# GKE NEG OUTPUTS
# ==============================================================================

output "gke_neg_self_links" {
  description = "Map of backend name to list of pre-created GKE NEG self_links"
  value = {
    for k, v in var.backends.services : k => [
      for zone in v.gke_neg.zones :
      google_compute_network_endpoint_group.gke["${k}/${zone}"].self_link
    ] if v.gke_neg != null
  }
}

# ==============================================================================
# SSL CERTIFICATE OUTPUTS
# ==============================================================================

output "ssl_certificate_id" {
  description = "ID of the regional SSL certificate (if created)"
  value       = var.domain.enable_https && var.domain.create_ssl_certificate ? google_compute_region_ssl_certificate.regional_gateway[0].id : null
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = var.domain.enable_https && var.domain.create_ssl_certificate ? google_compute_region_ssl_certificate.regional_gateway[0].name : var.domain.ssl_certificate_name
}

# ==============================================================================
# FIREWALL OUTPUTS
# ==============================================================================

output "firewall_rule_health_checks_id" {
  description = "ID of the firewall rule allowing health checks"
  value       = var.firewall.create_rules ? google_compute_firewall.health_checks[0].id : null
}

# ==============================================================================
# CONFIGURATION SUMMARY
# ==============================================================================

output "enabled_backends" {
  description = "List of enabled backend names"
  value       = keys(var.backends.services)
}

output "default_backend" {
  description = "Default backend name"
  value       = var.backends.default
}

output "routing_rules_count" {
  description = "Number of routing rules configured"
  value = {
    model_rules  = length(var.routing.model_rules)
    header_rules = length(var.routing.header_rules)
    path_rules   = length(var.routing.path_rules)
  }
}

# ==============================================================================
# BODY-BASED ROUTING (BBR) OUTPUTS
# ==============================================================================

output "bbr_ext_proc_service_url" {
  description = "URL of the BBR ext_proc Cloud Run service"
  value       = var.body_based_routing.enabled ? module.bbr_ext_proc[0].cloud_run_service_url : null
}

output "bbr_ext_proc_backend_id" {
  description = "ID of the BBR ext_proc backend service"
  value       = var.body_based_routing.enabled ? module.bbr_ext_proc[0].backend_service_id : null
}

output "bbr_ext_proc_backend_self_link" {
  description = "Self link of the BBR ext_proc backend service"
  value       = var.body_based_routing.enabled ? module.bbr_ext_proc[0].backend_service_self_link : null
}

output "body_based_routing_enabled" {
  description = "Whether body-based routing is enabled"
  value       = var.body_based_routing.enabled
}

# ==============================================================================
# MODEL ARMOR OUTPUTS
# ==============================================================================

output "model_armor_extension_id" {
  description = "ID of the Model Armor traffic extension"
  value       = var.security.model_armor.enabled ? google_network_services_lb_traffic_extension.model_armor[0].id : null
}

# ==============================================================================
# EFFECTIVE VALUES
# ==============================================================================

output "effective_gateway_ip" {
  description = "The active gateway IP address (shared VIP for HTTP and HTTPS)"
  value       = google_compute_address.shared_vip.address
}

output "effective_https_gateway_ip" {
  description = "The HTTPS gateway IP address (same as HTTP due to shared VIP)"
  value       = var.domain.enable_https ? google_compute_address.shared_vip.address : null
}

output "preferred_gateway_ip" {
  description = "The preferred gateway IP address (shared VIP for all traffic)"
  value       = google_compute_address.shared_vip.address
}

output "shared_vip_id" {
  description = "ID of the shared VIP address resource"
  value       = google_compute_address.shared_vip.id
}

output "load_balancing_scheme" {
  description = "Load balancing scheme (always INTERNAL_MANAGED)"
  value       = local.lb_scheme
}
