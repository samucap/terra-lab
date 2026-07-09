# Cloud SQL PostgreSQL (dev) — private IP only via VPC Private Service Access.
# Internal services on the same VPC (e.g. Cloud Run Direct VPC egress) reach
# the instance at the private IP on port 5432.

# ---------------------------------------------------------------------------
# APIs (TF-owned; leave enabled on destroy so other project resources keep working)
# ---------------------------------------------------------------------------

resource "google_project_service" "sql_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "compute.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_compute_network" "vpc" {
  name    = var.network_id
  project = var.project_id

  depends_on = [google_project_service.sql_apis]
}

# ---------------------------------------------------------------------------
# Private Service Access (required for Cloud SQL private IP)
# Allocates a peering range and peers the VPC with Google's service producer.
# Destroyed with the stack (no ABANDON) so ranges/peering do not leak cost.
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "sql_private_ip_range" {
  project       = var.project_id
  name          = "${var.db_instance_name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = data.google_compute_network.vpc.id

  depends_on = [google_project_service.sql_apis]
}

resource "google_service_networking_connection" "sql_private_vpc" {
  network                 = data.google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.sql_private_ip_range.name]

  depends_on = [google_project_service.sql_apis]
}

# ---------------------------------------------------------------------------
# Instance name suffix — Cloud SQL names stay reserved ~1 week after delete
# ---------------------------------------------------------------------------

resource "random_id" "sql_suffix" {
  byte_length = 2
}

# ---------------------------------------------------------------------------
# PostgreSQL development instance (private IP, no public IPv4)
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = "${var.db_instance_name}-${random_id.sql_suffix.hex}"
  database_version    = var.db_version
  region              = var.project_region
  deletion_protection = var.db_deletion_protection

  depends_on = [google_service_networking_connection.sql_private_vpc]

  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.db_disk_size_gb
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = var.db_backup_enabled
      point_in_time_recovery_enabled = false
      start_time                     = "04:00"
      transaction_log_retention_days = 1
      backup_retention_settings {
        retained_backups = 3
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 5
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = false
      record_client_address   = false
    }

    user_labels = {
      env     = "dev"
      service = "orion"
    }
  }
}

resource "google_sql_database" "app" {
  project         = var.project_id
  name            = var.orion_secrets["POSTGRES_DB"]
  instance        = google_sql_database_instance.postgres.name
  deletion_policy = "ABANDON"
}

resource "google_sql_user" "app" {
  project  = var.project_id
  name     = var.orion_secrets["POSTGRES_USER"]
  password = var.orion_secrets["POSTGRES_PASSWORD"]
  instance = google_sql_database_instance.postgres.name
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.postgres.name
}

output "sql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance), useful for the Auth Proxy"
  value       = google_sql_database_instance.postgres.connection_name
}

output "sql_private_ip" {
  description = "Private IP for internal VPC clients (set as POSTGRES_HOST on Orion)"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "sql_database_name" {
  description = "Application database name"
  value       = google_sql_database.app.name
  sensitive   = true
}
