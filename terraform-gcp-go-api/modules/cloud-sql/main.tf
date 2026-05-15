variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "deployment_name" {
  type = string
}

variable "db_tier" {
  type = string
}

variable "db_version" {
  type = string
}

variable "db_name" {
  type = string
}

variable "network_id" {
  type        = string
  description = "VPC network self-link for private IP allocation."
}

variable "service_account" {
  type        = string
  description = "Cloud Run service account email for IAM auth."
}

variable "labels" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Random suffix to allow instance re-creation (Cloud SQL names are reserved
# for ~1 week after deletion)
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 2
}

# ---------------------------------------------------------------------------
# Cloud SQL PostgreSQL instance - private IP only, IAM auth
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = "${var.deployment_name}-db-${random_id.suffix.hex}"
  database_version = var.db_version
  region           = var.region

  settings {
    tier              = var.db_tier
    disk_autoresize   = true
    disk_size         = 10
    disk_type         = "PD_SSD"
    availability_type = "ZONAL"
    user_labels       = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    location_preference {
      zone = var.zone
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    insights_config {
      query_insights_enabled = false
    }
  }

  deletion_protection = true
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

resource "google_sql_database" "main" {
  project         = var.project_id
  name            = var.db_name
  instance        = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"
}

# ---------------------------------------------------------------------------
# IAM database user (maps Cloud Run SA -> PostgreSQL role)
# The user name format for CLOUD_IAM_SERVICE_ACCOUNT is the SA email
# WITHOUT the .gserviceaccount.com domain suffix — just account_id@project.iam.
# ---------------------------------------------------------------------------

locals {
  sa_account_id = split("@", var.service_account)[0]
}

resource "google_sql_user" "iam_user" {
  project         = var.project_id
  instance        = google_sql_database_instance.main.name
  name            = "${local.sa_account_id}@${var.project_id}.iam"
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = "ABANDON"
}
