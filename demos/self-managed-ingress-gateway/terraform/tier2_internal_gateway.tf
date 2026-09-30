locals {
  vertex_ai_endpoint = "${var.region}-aiplatform.googleapis.com"

  agent_engine_path = "/v1/projects/${var.producer_project_id}/locations/${var.region}/reasoningEngines/${var.reasoning_engine_id}:streamQuery"
}

# -----------------------------------------------------------------------------
# Tier 2 - PSC NEG to Vertex AI
# -----------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "vertex_ai_psc_neg" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name = "vertex-ai-psc-neg"

  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = local.vertex_ai_endpoint
}

# -----------------------------------------------------------------------------
# Tier 2 - Regional Internal Application Load Balancer
# -----------------------------------------------------------------------------

resource "google_compute_address" "internal_lb" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name         = "self-managed-ingress-internal-lb"
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.producer.id
}

resource "google_compute_forwarding_rule" "internal_lb" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name                  = "self-managed-ingress-internal-lb"
  load_balancing_scheme = "INTERNAL_MANAGED"

  network    = google_compute_network.producer.id
  subnetwork = google_compute_subnetwork.producer.id

  ip_address = google_compute_address.internal_lb.id
  port_range = "80"

  target = google_compute_region_target_http_proxy.internal.id

  allow_global_access = true
}

resource "google_compute_region_target_http_proxy" "internal" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name    = "self-managed-ingress-internal"
  url_map = google_compute_region_url_map.internal.id
}

resource "google_compute_region_url_map" "internal" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name            = "self-managed-ingress-internal"
  default_service = google_compute_region_backend_service.vertex_ai.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "agent"
  }

  path_matcher {
    name            = "agent"
    default_service = google_compute_region_backend_service.vertex_ai.id

    route_rules {
      priority = 1

      match_rules {
        prefix_match = "/chat"
      }

      service = google_compute_region_backend_service.vertex_ai.id

      route_action {
        url_rewrite {
          host_rewrite = local.vertex_ai_endpoint
          path_prefix_rewrite = local.agent_engine_path
        }
      }
    }
  }
}

resource "google_compute_region_backend_service" "vertex_ai" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name                  = "vertex-ai-backend"
  protocol              = "HTTPS"
  load_balancing_scheme = "INTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.vertex_ai_psc_neg.id
  }
}