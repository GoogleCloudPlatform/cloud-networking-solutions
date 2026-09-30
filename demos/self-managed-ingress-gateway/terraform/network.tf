# -----------------------------------------------------------------------------
# Tier 1 - Consumer Network
# -----------------------------------------------------------------------------

resource "google_compute_network" "consumer" {
  provider = google.consumer
  project  = var.consumer_project_id

  name                    = var.consumer_network_name
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.consumer
  ]
}

resource "google_compute_subnetwork" "consumer" {
  provider = google.consumer
  project  = var.consumer_project_id
  region   = var.region

  name          = "self-managed-ingress-consumer"
  network       = google_compute_network.consumer.id
  ip_cidr_range = "10.10.0.0/24"
}

# -----------------------------------------------------------------------------
# Tier 2 - Producer Network
# -----------------------------------------------------------------------------

resource "google_compute_network" "producer" {
  provider = google.producer
  project  = var.producer_project_id

  name                    = var.producer_network_name
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.producer
  ]
}

resource "google_compute_subnetwork" "producer" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name          = "self-managed-ingress-producer"
  network       = google_compute_network.producer.id
  ip_cidr_range = "10.20.0.0/24"
}

resource "google_compute_subnetwork" "producer_proxy_only" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name          = "self-managed-ingress-proxy-only"
  network       = google_compute_network.producer.id
  ip_cidr_range = "10.20.1.0/24"

  purpose = "REGIONAL_MANAGED_PROXY"
  role    = "ACTIVE"
}
resource "google_compute_subnetwork" "producer_psc_nat" {
  provider = google.producer
  project  = var.producer_project_id
  region   = var.region

  name          = "self-managed-ingress-psc-nat"
  network       = google_compute_network.producer.id
  ip_cidr_range = "10.20.2.0/24"

  purpose = "PRIVATE_SERVICE_CONNECT"
}