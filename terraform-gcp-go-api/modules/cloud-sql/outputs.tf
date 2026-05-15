output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance)."
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip" {
  description = "Private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.main.private_ip_address
}

output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.main.name
}

output "database_name" {
  description = "Name of the PostgreSQL database."
  value       = google_sql_database.main.name
}

output "iam_db_user" {
  description = "IAM database username (short form for PostgreSQL login)."
  value       = google_sql_user.iam_user.name
}
