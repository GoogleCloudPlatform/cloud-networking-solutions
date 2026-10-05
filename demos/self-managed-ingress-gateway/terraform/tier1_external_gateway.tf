# -----------------------------------------------------------------------------
# Tier 1 - PSC NEG to Service Attachment
# -----------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "tier1_psc" {
  provider = google.consumer
  project  = var.consumer_project_id
  region   = var.region

  name                  = "tier2-psc-neg"
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"

  psc_target_service = google_compute_service_attachment.tier2.id

  network = google_compute_network.consumer.id
  subnetwork = google_compute_subnetwork.consumer.id
}

# -----------------------------------------------------------------------------
# Tier 1 - External Global Application Load Balancer
# -----------------------------------------------------------------------------

resource "google_compute_backend_service" "tier1" {
  provider = google.consumer
  project  = var.consumer_project_id

  name                  = "self-managed-ingress-tier2-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.tier1_psc.id
  }
}

resource "google_compute_url_map" "external" {
  provider = google.consumer
  project  = var.consumer_project_id

  name            = "self-managed-ingress-external"
  default_service = google_compute_backend_service.tier1.id

  host_rule {
    hosts = var.agent_hostnames

    path_matcher = "agent"
  }

  path_matcher {
    name            = "agent"
    default_service = google_compute_backend_service.tier1.id
  }
}

resource "google_compute_global_address" "external" {
  provider = google.consumer
  project  = var.consumer_project_id

  name = "self-managed-ingress-ip"
}

resource "google_compute_target_http_proxy" "external" {
  provider = google.consumer
  project  = var.consumer_project_id

  name    = "self-managed-ingress-http-proxy"
  url_map = google_compute_url_map.external.id
}

resource "google_compute_global_forwarding_rule" "external_http" {
  provider = google.consumer
  project  = var.consumer_project_id

  name = "self-managed-ingress-http"

  load_balancing_scheme = "EXTERNAL_MANAGED"

  ip_address = google_compute_global_address.external.id
  port_range = "80"

  target = google_compute_target_http_proxy.external.id
}