output "consumer_network" {
  value = google_compute_network.consumer.id
}

output "producer_network" {
  value = google_compute_network.producer.id
}

output "consumer_subnet" {
  value = google_compute_subnetwork.consumer.id
}

output "producer_subnet" {
  value = google_compute_subnetwork.producer.id
}

output "producer_proxy_only_subnet" {
  value = google_compute_subnetwork.producer_proxy_only.id
}

output "producer_psc_nat_subnet" {
  value = google_compute_subnetwork.producer_psc_nat.id
}

output "vertex_ai_psc_neg_id" {
  value = google_compute_region_network_endpoint_group.vertex_ai_psc_neg.id
}