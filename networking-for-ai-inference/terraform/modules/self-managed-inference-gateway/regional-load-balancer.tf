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
# REGIONAL INTERNAL APPLICATION LOAD BALANCER
# ==============================================================================
#
# This file creates a regional internal Application Load Balancer (ALB) that
# supports body-based routing via LbRouteExtension.
#
# Key capabilities:
# 1. ext_proc with mode_override to request body processing
# 2. Re-evaluation of routing rules after ext_proc injects headers
# 3. True body-based routing for OpenAI-compatible API requests
#
# ==============================================================================

# ==============================================================================
# REGIONAL STATIC IP ADDRESS
# ==============================================================================
#
# Note: For INTERNAL_MANAGED load balancers (regional internal Application LB),
# we cannot reserve a static IP in the proxy-only subnet. The VIP is allocated
# from the proxy subnet range when the forwarding rule is created.
#
# We let the forwarding rule auto-assign an IP and read it from the output.
# ==============================================================================

# Static IP is not supported for INTERNAL_MANAGED load balancers with proxy-only subnets
# The IP is auto-assigned from the proxy subnet when the forwarding rule is created

# ==============================================================================
# REGIONAL URL MAP
# ==============================================================================

resource "google_compute_region_url_map" "regional_gateway" {
  name        = "${local.resource_prefix}-url-map"
  project     = var.project_id
  region      = var.region
  description = "URL map for self managed inference gateway with flexible routing"

  # Default backend service
  default_service = local.default_backend_id

  # Host rule for the gateway domain
  # Include wildcard (*) to match requests by IP address or any hostname
  host_rule {
    hosts        = [var.domain.name, "*"]
    path_matcher = "inference-routes"
  }

  # Path matcher with configurable routing rules
  path_matcher {
    name            = "inference-routes"
    default_service = local.default_backend_id

    # ==================================================================
    # HEADER-BASED ROUTING (X-Backend-Type direct routing)
    # ==================================================================

    # Route based on X-Backend-Type header (allows ext_proc to set backend directly)
    dynamic "route_rules" {
      for_each = local.backend_ids
      content {
        priority = 1 + index(keys(local.backend_ids), route_rules.key)
        service  = route_rules.value

        match_rules {
          header_matches {
            header_name = "X-Backend-Type"
            exact_match = route_rules.key
          }
        }
      }
    }

    # ==================================================================
    # PATH-BASED ROUTING (from routing.path_rules)
    # Placed before model-based routing to allow lower priority numbers
    # for path prefix rewriting (e.g., /security/ → /)
    # ==================================================================

    dynamic "route_rules" {
      for_each = { for idx, rule in var.routing.path_rules : idx => rule }
      content {
        priority = route_rules.value.priority
        service  = local.backend_ids[route_rules.value.backend]

        match_rules {
          prefix_match = route_rules.value.path_match
        }

        # Optional URL rewrite for path prefix stripping
        dynamic "route_action" {
          for_each = route_rules.value.url_rewrite != null ? [1] : []
          content {
            url_rewrite {
              path_prefix_rewrite = route_rules.value.url_rewrite.path_prefix_rewrite
              host_rewrite        = route_rules.value.url_rewrite.host_rewrite
            }
          }
        }
      }
    }

    # ==================================================================
    # MODEL-BASED ROUTING (from routing.model_rules)
    # ==================================================================

    dynamic "route_rules" {
      for_each = { for idx, rule in var.routing.model_rules : idx => rule }
      content {
        priority = route_rules.value.priority
        service  = local.backend_ids[route_rules.value.backend]

        match_rules {
          # Add path prefix match for URL rewrite to work correctly
          # The pathPrefixRewrite replaces this matched prefix
          prefix_match = route_rules.value.url_rewrite != null ? "/v1/" : null

          header_matches {
            header_name  = var.body_based_routing.model_header_name
            prefix_match = route_rules.value.model_prefix
          }
        }

        # Optional URL rewrite
        dynamic "route_action" {
          for_each = route_rules.value.url_rewrite != null ? [1] : []
          content {
            url_rewrite {
              path_prefix_rewrite = route_rules.value.url_rewrite.path_prefix_rewrite
              host_rewrite        = route_rules.value.url_rewrite.host_rewrite
            }
          }
        }
      }
    }

    # ==================================================================
    # HEADER-BASED ROUTING (from routing.header_rules)
    # ==================================================================

    dynamic "route_rules" {
      for_each = { for idx, rule in var.routing.header_rules : idx => rule }
      content {
        priority = route_rules.value.priority
        service  = local.backend_ids[route_rules.value.backend]

        match_rules {
          dynamic "header_matches" {
            for_each = route_rules.value.match_type == "exact" ? [1] : []
            content {
              header_name = route_rules.value.header_name
              exact_match = route_rules.value.match_value
            }
          }
          dynamic "header_matches" {
            for_each = route_rules.value.match_type == "prefix" ? [1] : []
            content {
              header_name  = route_rules.value.header_name
              prefix_match = route_rules.value.match_value
            }
          }
          dynamic "header_matches" {
            for_each = route_rules.value.match_type == "regex" ? [1] : []
            content {
              header_name = route_rules.value.header_name
              regex_match = route_rules.value.match_value
            }
          }
        }
      }
    }

    # ==================================================================
    # FALLBACK: Health check endpoint
    # ==================================================================

    route_rules {
      priority = 1000
      service  = local.default_backend_id

      match_rules {
        prefix_match = "/health"
      }
    }
  }
}

# ==============================================================================
# REGIONAL HTTP-TO-HTTPS REDIRECT URL MAP
# ==============================================================================
# When HTTPS is enabled, the HTTP proxy uses this redirect-only URL map
# to redirect all HTTP traffic to HTTPS

resource "google_compute_region_url_map" "http_redirect" {
  count = var.domain.enable_https ? 1 : 0

  name        = "${local.resource_prefix}-http-redirect"
  project     = var.project_id
  region      = var.region
  description = "URL map for HTTP to HTTPS redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ==============================================================================
# REGIONAL HTTP TARGET PROXY
# ==============================================================================

resource "google_compute_region_target_http_proxy" "regional_gateway" {
  name    = "${local.resource_prefix}-regional-http-proxy"
  project = var.project_id
  region  = var.region

  # When HTTPS is enabled, use the redirect URL map; otherwise use the main URL map
  url_map = var.domain.enable_https ? google_compute_region_url_map.http_redirect[0].id : google_compute_region_url_map.regional_gateway.id

  # Keep description constant to avoid forcing replacement when switching modes
  description = "Regional HTTP proxy for self managed inference gateway with body-based routing"
}

# ==============================================================================
# REGIONAL HTTPS TARGET PROXY
# ==============================================================================

resource "google_compute_region_target_https_proxy" "regional_gateway" {
  count = var.domain.enable_https ? 1 : 0

  name    = "${local.resource_prefix}-regional-https-proxy"
  project = var.project_id
  region  = var.region
  url_map = google_compute_region_url_map.regional_gateway.id

  # Use either Certificate Manager or self-managed certificates (mutually exclusive)
  ssl_certificates = var.domain.use_certificate_manager ? null : (
    var.domain.create_ssl_certificate ? [google_compute_region_ssl_certificate.regional_gateway[0].id] : null
  )

  # Certificate Manager certificate (preferred for production)
  certificate_manager_certificates = var.domain.use_certificate_manager && var.domain.certificate_manager_id != null ? [
    var.domain.certificate_manager_id
  ] : null

  description = "Regional HTTPS proxy for self managed inference gateway with TLS termination"
}

# ==============================================================================
# REGIONAL SSL CERTIFICATE
# ==============================================================================

resource "google_compute_region_ssl_certificate" "regional_gateway" {
  count = var.domain.enable_https && var.domain.create_ssl_certificate ? 1 : 0

  name        = "${local.resource_prefix}-regional-ssl-cert"
  project     = var.project_id
  region      = var.region
  description = "SSL certificate for regional self managed inference gateway"

  # Use provided certificate or generate self-signed
  private_key = var.domain.ssl_private_key != null ? var.domain.ssl_private_key : tls_private_key.regional_self_signed[0].private_key_pem
  certificate = var.domain.ssl_certificate_pem != null ? var.domain.ssl_certificate_pem : tls_self_signed_cert.regional_self_signed[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# Self-signed certificate for development (when no certificate provided)
resource "tls_private_key" "regional_self_signed" {
  count = var.domain.enable_https && var.domain.create_ssl_certificate && var.domain.ssl_private_key == null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "regional_self_signed" {
  count = var.domain.enable_https && var.domain.create_ssl_certificate && var.domain.ssl_certificate_pem == null ? 1 : 0

  private_key_pem = tls_private_key.regional_self_signed[0].private_key_pem

  subject {
    common_name  = var.domain.name
    organization = "Self Managed Inference Gateway"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [var.domain.name]
}

# ==============================================================================
# SHARED INTERNAL IP ADDRESS
# ==============================================================================
#
# For HTTP to HTTPS redirect to work, both forwarding rules must share the same
# IP address. This requires a reserved IP with purpose = SHARED_LOADBALANCER_VIP.
#
# Reference: https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-http-to-https-redirect
#
# ==============================================================================

resource "google_compute_address" "shared_vip" {
  name         = "${local.resource_prefix}-shared-ip"
  project      = var.project_id
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = var.vpc.subnet_id
  purpose      = "SHARED_LOADBALANCER_VIP"
  # Note: description forces replacement, so we don't set it
}

# ==============================================================================
# REGIONAL FORWARDING RULES
# ==============================================================================

# HTTP Forwarding Rule
resource "google_compute_forwarding_rule" "regional_http" {
  name       = "${local.resource_prefix}-http-shared"
  project    = var.project_id
  region     = var.region
  target     = google_compute_region_target_http_proxy.regional_gateway.id
  port_range = "80"
  # Use shared VIP for HTTP to HTTPS redirect
  ip_address = google_compute_address.shared_vip.id

  load_balancing_scheme = local.lb_scheme
  network               = var.vpc.id
  subnetwork            = var.vpc.subnet_id

  labels = local.common_labels
}

# HTTPS Forwarding Rule
resource "google_compute_forwarding_rule" "regional_https" {
  count = var.domain.enable_https ? 1 : 0

  name       = "${local.resource_prefix}-https-shared"
  project    = var.project_id
  region     = var.region
  target     = google_compute_region_target_https_proxy.regional_gateway[0].id
  port_range = "443"
  # Use same shared VIP as HTTP for redirect to work
  ip_address = google_compute_address.shared_vip.id

  load_balancing_scheme = local.lb_scheme
  network               = var.vpc.id
  subnetwork            = var.vpc.subnet_id

  labels = local.common_labels
}

# ==============================================================================
# BACKEND SERVICES
# ==============================================================================
#
# Backend services are now created in backends.tf using a flexible for_each
# pattern. This allows users to define custom backends without modifying
# this file. See backends.tf and var.backends for configuration details.
#
# ==============================================================================
