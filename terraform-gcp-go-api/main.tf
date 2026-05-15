locals {
  apis = [
    "compute.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "sql-component.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Service account for Cloud Run (used for IAM-based Cloud SQL auth)
# ---------------------------------------------------------------------------

resource "google_service_account" "cloud_run" {
  project      = var.project_id
  account_id   = "${var.deployment_name}-run-sa"
  display_name = "Cloud Run SA for ${var.deployment_name}"
}

resource "google_project_iam_member" "cloud_run_roles" {
  for_each = toset([
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc"

  project_id      = var.project_id
  region          = var.region
  deployment_name = var.deployment_name

  depends_on = [google_project_service.apis]
}

module "cloud_sql" {
  source = "./modules/cloud-sql"

  project_id      = var.project_id
  region          = var.region
  zone            = var.zone
  deployment_name = var.deployment_name
  db_tier         = var.db_tier
  db_version      = var.db_version
  db_name         = var.db_name
  network_id      = module.vpc.network_id
  service_account = google_service_account.cloud_run.email
  labels          = var.labels

  depends_on = [module.vpc]
}

module "cloud_run" {
  source = "./modules/cloud-run"

  project_id      = var.project_id
  region          = var.region
  deployment_name = var.deployment_name
  container_image = var.container_image

  service_account_email = google_service_account.cloud_run.email
  network_name          = module.vpc.network_name
  subnet_name           = module.vpc.subnet_name

  db_private_ip     = module.cloud_sql.private_ip
  db_name           = module.cloud_sql.database_name
  db_user           = module.cloud_sql.iam_db_user
  db_connection_name = module.cloud_sql.connection_name

  min_instances = var.cloud_run_min_instances
  max_instances = var.cloud_run_max_instances
  cpu           = var.cloud_run_cpu
  memory        = var.cloud_run_memory
  concurrency   = var.cloud_run_concurrency
  labels        = var.labels

  depends_on = [module.cloud_sql, google_project_iam_member.cloud_run_roles]
}

module "load_balancer" {
  source = "./modules/load-balancer"

  project_id      = var.project_id
  region          = var.region
  deployment_name = var.deployment_name
  domain_name     = var.domain_name

  cloud_run_service_name = module.cloud_run.service_name
  rate_limit_per_minute  = var.cloud_armor_rate_limit
  labels                 = var.labels

  depends_on = [module.cloud_run]
}
