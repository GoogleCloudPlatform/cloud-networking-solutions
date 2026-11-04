resource "google_compute_firewall" "allow_iap_ssh" {
  provider = google.producer
  project  = var.producer_project_id

  name    = "allow-iap-ssh"
  network = google_compute_network.producer.name

  direction = "INGRESS"

  source_ranges = [
    "35.235.240.0/20"
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = [
    "producer-test-vm"
  ]
}

resource "google_service_account" "producer_test_vm" {
  provider = google.producer
  project  = var.producer_project_id

  account_id   = "producer-test-vm"
  display_name = "Producer test VM"
}



resource "google_compute_instance" "producer_test_vm" {
  provider = google.producer
  project  = var.producer_project_id
  zone     = "${var.region}-a"

  name         = "producer-test-vm"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = google_compute_network.producer.id
    subnetwork = google_compute_subnetwork.producer.id

    # Sin access_config => sin IP pública
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y curl jq
  EOT

  tags = ["producer-test-vm"]

  depends_on = [
    google_project_service.producer
  ]

  allow_stopping_for_update = true

  service_account {
    email = google_service_account.producer_test_vm.email

    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}