output "load_balancer_ip" {
  description = "Global external IP of the HTTPS load balancer."
  value       = module.load_balancer.lb_external_ip
}

output "cloud_run_uri" {
  description = "Cloud Run service URI (internal, not publicly accessible)."
  value       = module.cloud_run.service_uri
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL instance connection name."
  value       = module.cloud_sql.connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address."
  value       = module.cloud_sql.private_ip
}

output "dns_instructions" {
  description = "DNS A record to create for your domain."
  value       = "Create an A record: ${var.domain_name} -> ${module.load_balancer.lb_external_ip}"
}
