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
# SELF MANAGED INFERENCE GATEWAY MODULE
# ==============================================================================
#
# This module creates a Regional External Application Load Balancer with
# body-based routing capabilities and multi-backend support for:
# - Vertex AI prediction endpoints
# - GKE InferencePool endpoints
#
# Regional ALB is used exclusively to support:
# - LbRouteExtension with mode_override for body-based routing
# - LbTrafficExtension for Model Armor integration
# - Dynamic forwarding based on request body content
#
# The module orchestrates the following components:
# 1. Regional Load Balancer (regional-load-balancer.tf)
# 2. Health Checks (health-checks.tf) - Backend health monitoring
# 3. Firewall Rules (firewall.tf) - Network security for health checks
# 4. BBR ext_proc (bbr-ext-proc.tf) - Body-Based Router ext_proc service
# 5. Route Extension (route-extension.tf) - Body-based routing configuration
# 6. Model Armor (model-armor.tf) - Traffic extension for security
#
# ==============================================================================

# All locals are now consolidated in locals.tf for easier maintenance

# ==============================================================================
# MODULE COMPONENTS
# ==============================================================================

# The following resources are defined in their respective files:
#
# regional-load-balancer.tf:
#   - google_compute_region_url_map.regional_gateway (URL map for routing)
#   - google_compute_region_target_http_proxy.regional_gateway (HTTP proxy)
#   - google_compute_region_target_https_proxy.regional_gateway (HTTPS proxy)
#   - google_compute_forwarding_rule.regional_http (HTTP forwarding rule)
#   - google_compute_forwarding_rule.regional_https (HTTPS forwarding rule)
#   - google_compute_region_backend_service.regional_gke (GKE backend)
#   - google_compute_region_backend_service.regional_vertex_ai (Vertex AI backend)
#   - google_compute_region_backend_service.regional_bbr_ext_proc (BBR backend)
#   - google_compute_region_health_check.regional_gke (GKE health check)
#   - google_compute_region_network_endpoint_group.regional_vertex_ai (Vertex AI NEG)
#   - google_compute_region_network_endpoint_group.regional_bbr_ext_proc (BBR NEG)
#   - google_compute_region_ssl_certificate.regional_gateway (SSL cert)
#
# health-checks.tf:
#   - google_compute_health_check.vertex_ai (Vertex AI health check - disabled)
#   - google_compute_health_check.gke (GKE health check - disabled, using regional)
#
# firewall.tf:
#   - google_compute_firewall.health_checks (allow health check traffic)
#
# bbr-ext-proc.tf:
#   - google_service_account.bbr_ext_proc (service account)
#   - google_cloud_run_service.bbr_ext_proc (ext_proc Cloud Run service)
#   - google_cloud_run_service_iam_member.bbr_ext_proc_invoker (IAM)
#
# route-extension.tf (commented - manual configuration needed):
#   - google_network_services_lb_route_extension.bbr (body-based routing)
#
# model-armor.tf:
#   - google_network_services_lb_traffic_extension.model_armor (security)
#
# ==============================================================================
