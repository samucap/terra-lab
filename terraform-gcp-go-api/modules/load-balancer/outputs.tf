output "lb_external_ip" {
  description = "Static external IP address of the load balancer."
  value       = google_compute_global_address.lb.address
}

output "ssl_certificate_name" {
  description = "Name of the Google-managed SSL certificate."
  value       = google_compute_managed_ssl_certificate.main.name
}

output "security_policy_name" {
  description = "Name of the Cloud Armor security policy."
  value       = google_compute_security_policy.armor.name
}
