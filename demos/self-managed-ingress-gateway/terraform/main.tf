locals {
  resource_prefix = var.name_prefix

  public_frontend_name = "${local.resource_prefix}-tier1"
  internal_backend_map = {
    for agent_name, cfg in var.agents : agent_name => {
      host        = cfg.host
      path_prefix = cfg.path_prefix
      rewrite_to  = cfg.rewrite_path
      backend_url = "https://${cfg.backend_host}"
    }
  }
}

# -----------------------------------------------------------------------------
# Shared VPC and network primitives
# -----------------------------------------------------------------------------
resource "google_compute_network" "main" {
  name                    = "${local.resource_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "${local.resource_prefix}-subnet-public"
  ip_cidr_range = "10.10.0.0/24"
  network       = google_compute_network.main.id
  region        = var.region
}

resource "google_compute_subnetwork" "private" {
  name          = "${local.resource_prefix}-subnet-private"
  ip_cidr_range = "10.20.0.0/24"
  network       = google_compute_network.main.id
  region        = var.region
}

resource "google_compute_subnetwork" "proxy" {
  name          = "${local.resource_prefix}-subnet-proxy"
  ip_cidr_range = "10.30.0.0/24"
  network       = google_compute_network.main.id
  region        = var.region
  purpose       = "INTERNAL_HTTPS_LOAD_BALANCER"
}

resource "google_compute_subnetwork" "psc" {
  name          = "${local.resource_prefix}-subnet-psc"
  ip_cidr_range = "10.40.0.0/24"
  network       = google_compute_network.main.id
  region        = var.region
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# -----------------------------------------------------------------------------
# Tier 1: global external front door
# -----------------------------------------------------------------------------
resource "google_compute_global_address" "tier1_ip" {
  name = "${local.resource_prefix}-tier1-ip"
}

resource "google_compute_global_forwarding_rule" "tier1_https" {
  name                  = "${local.resource_prefix}-tier1-https"
  target                = google_compute_target_https_proxy.tier1.self_link
  port_range            = "443"
  ip_address            = google_compute_global_address.tier1_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_target_https_proxy" "tier1" {
  name             = "${local.resource_prefix}-tier1-proxy"
  url_map          = google_compute_url_map.tier1.self_link
  ssl_certificates = var.enable_tls ? [google_compute_managed_ssl_certificate.tier1[0].self_link] : []
}

resource "google_compute_url_map" "tier1" {
  name        = "${local.resource_prefix}-tier1-urlmap"
  description = "Global front door routing by host name to the appropriate internal tier-2 backend"

  default_service = google_compute_backend_service.tier1_default.self_link

  dynamic "host_rule" {
    for_each = var.agents
    content {
      hosts        = [host_rule.value.host]
      path_matcher = "path-${host_rule.key}"
    }
  }

  dynamic "path_matcher" {
    for_each = var.agents
    content {
      name            = "path-${path_matcher.key}"
      default_service = google_compute_backend_service.tier1_default.self_link

      route_rules {
        priority = 1
        service  = google_compute_backend_service.agent_internal[path_matcher.key].self_link

        match_rules {
          prefix_match = path_matcher.value.path_prefix
        }
      }
    }
  }
}

resource "google_compute_backend_service" "tier1_default" {
  name          = "${local.resource_prefix}-tier1-default"
  description   = "Fallback backend for unknown hostnames"
  protocol      = "HTTPS"
  port_name     = "https"
  health_checks = [google_compute_health_check.default.self_link]

  backend {
    group = google_compute_region_network_endpoint_group.psc_tier1_default.self_link
  }
}

resource "google_compute_backend_service" "agent_internal" {
  for_each = var.agents

  name          = "${local.resource_prefix}-tier1-${each.key}"
  description   = "Global backend for ${each.key} through the regional internal tier-2 gateway"
  protocol      = "HTTPS"
  port_name     = "https"
  health_checks = [google_compute_health_check.default.self_link]

  backend {
    group = google_compute_region_network_endpoint_group.psc_tier2[each.key].self_link
  }
}

resource "google_compute_region_network_endpoint_group" "psc_tier2" {
  for_each = var.agents

  name                  = "${local.resource_prefix}-${each.key}-psc-neg"
  region                = var.region
  network               = google_compute_network.main.id
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"

  psc_target_service = "projects/${var.project_id}/regions/${var.region}/serviceAttachments/${local.resource_prefix}-${each.key}-tier2-service-attachment"
}

resource "google_compute_region_network_endpoint_group" "psc_tier1_default" {
  name                  = "${local.resource_prefix}-default-psc-neg"
  region                = var.region
  network               = google_compute_network.main.id
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"

  psc_target_service = "projects/${var.project_id}/regions/${var.region}/serviceAttachments/${local.resource_prefix}-default-tier2-service-attachment"
}

resource "google_compute_health_check" "default" {
  name = "${local.resource_prefix}-healthcheck"

  https_health_check {
    port         = 443
    request_path = "/healthz"
  }
}

# -----------------------------------------------------------------------------
# Optional TLS certificate
# -----------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "tier1" {
  count = var.enable_tls ? 1 : 0

  name = "${local.resource_prefix}-tier1-cert"

  managed {
    domains = [for agent in var.agents : agent.host]
  }
}

# -----------------------------------------------------------------------------
# Tier 2: one regional internal load balancer per agent
# -----------------------------------------------------------------------------
resource "google_compute_region_backend_service" "agent_tier2_backend" {
  for_each = var.agents

  name                  = "${local.resource_prefix}-${each.key}-tier2-backend"
  region                = var.region
  protocol              = "HTTPS"
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.agent_backend[each.key].self_link]

  backend {
    group = google_compute_region_network_endpoint_group.vertex_psc[each.key].self_link
  }
}

resource "google_compute_region_network_endpoint_group" "vertex_psc" {
  for_each = var.agents

  name                  = "${local.resource_prefix}-${each.key}-vertex-psc-neg"
  network               = google_compute_network.main.id
  region                = var.region
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"

  psc_target_service = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region}/serviceAttachments/${local.resource_prefix}-${each.key}-vertex-psc"
}

resource "google_compute_health_check" "agent_backend" {
  for_each = var.agents

  name = "${local.resource_prefix}-${each.key}-backend-hc"

  https_health_check {
    port         = 443
    request_path = "/"
  }
}

resource "google_compute_region_url_map" "agent_tier2" {
  for_each = var.agents

  name    = "${local.resource_prefix}-${each.key}-tier2-urlmap"
  region  = var.region
  project = var.project_id

  default_service = google_compute_region_backend_service.agent_tier2_backend[each.key].self_link

  host_rule {
    hosts        = [each.value.host]
    path_matcher = "agent-${each.key}"
  }

  path_matcher {
    name            = "agent-${each.key}"
    default_service = google_compute_region_backend_service.agent_tier2_backend[each.key].self_link

    route_rules {
      priority = 1
      service  = google_compute_region_backend_service.agent_tier2_backend[each.key].self_link
      match_rules {
        prefix_match = each.value.path_prefix
      }
      route_action {
        url_rewrite {
          path_prefix_rewrite = each.value.rewrite_path
          host_rewrite        = each.value.backend_host
        }
      }
    }
  }
}

resource "google_compute_forwarding_rule" "agent_tier2" {
  for_each = var.agents

  name                  = "${local.resource_prefix}-${each.key}-tier2-fwd"
  region                = var.region
  backend_service       = google_compute_region_backend_service.agent_tier2_backend[each.key].self_link
  load_balancing_scheme = "INTERNAL_MANAGED"
  ip_address            = google_compute_address.agent_tier2[each.key].self_link
  network               = google_compute_network.main.self_link
  subnetwork            = google_compute_subnetwork.private.self_link
  ip_protocol           = "TCP"
  ports                 = ["443"]
  depends_on            = [google_compute_subnetwork.proxy]
}

resource "google_compute_address" "agent_tier2" {
  for_each = var.agents

  name         = "${local.resource_prefix}-${each.key}-tier2-ip"
  region       = var.region
  subnetwork   = google_compute_subnetwork.private.self_link
  address_type = "INTERNAL"
}

# -----------------------------------------------------------------------------
# Policy enforcement placeholders
# -----------------------------------------------------------------------------
resource "google_iap_web_backend_service_iam_member" "agent_iap" {
  for_each = { for k, v in var.agents : k => v if v.iap_enabled && var.enable_iap }

  web_backend_service = google_compute_backend_service.agent_internal[each.key].name
  role                = "roles/iap.httpsResourceAccessor"
  member              = var.iap_member
}

resource "google_compute_security_policy" "model_armor" {
  count = var.enable_model_armor ? 1 : 0

  name = "${local.resource_prefix}-model-armor-policy"

  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

output "front_door_ip" {
  value = google_compute_global_address.tier1_ip.address
}

output "front_door_hostnames" {
  value = [for agent in var.agents : agent.host]
}

output "tier2_internal_ips" {
  value = {
    for k, v in google_compute_address.agent_tier2 : k => v.address
  }
}

output "agent_backend_routes" {
  value = {
    for k, v in var.agents : k => {
      host         = v.host
      path_prefix  = v.path_prefix
      rewrite_path = v.rewrite_path
      backend_host = v.backend_host
    }
  }
}
