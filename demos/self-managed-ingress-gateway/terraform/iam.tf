resource "google_project_iam_member" "iap_tunnel_user" {
  provider = google.producer
  project  = var.producer_project_id

  role   = "roles/iap.tunnelResourceAccessor"
  member = var.demo_admin_user
}

resource "google_project_iam_member" "os_login" {
  provider = google.producer
  project  = var.producer_project_id

  role   = "roles/compute.osLogin"
  member = var.demo_admin_user
}

resource "google_project_iam_member" "producer_test_vm_vertex_ai_user" {
  provider = google.producer
  project  = var.producer_project_id

  role   = "roles/aiplatform.user"
  member = "serviceAccount:${google_service_account.producer_test_vm.email}"
}