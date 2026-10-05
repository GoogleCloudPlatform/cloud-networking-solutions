resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "demo" {
  private_key_pem = tls_private_key.demo.private_key_pem

  subject {
    common_name  = "agent-a.example.com"
    organization = "Self Managed Ingress Gateway Demo"
  }

  dns_names = var.agent_hostnames

  validity_period_hours = 168 # 7 days

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "google_compute_ssl_certificate" "demo" {
  provider = google.consumer
  project  = var.consumer_project_id

  name        = "self-managed-ingress-demo-cert"
  private_key = tls_private_key.demo.private_key_pem
  certificate = tls_self_signed_cert.demo.cert_pem
}