variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "deployment_name" {
  type = string
}

# ---------------------------------------------------------------------------
# Custom-mode VPC (no auto-created subnets)
# ---------------------------------------------------------------------------

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = "${var.deployment_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# ---------------------------------------------------------------------------
# Private subnet for Cloud Run Direct VPC Egress
# ---------------------------------------------------------------------------

resource "google_compute_subnetwork" "cloud_run" {
  project                  = var.project_id
  name                     = "${var.deployment_name}-subnet"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = "10.0.0.0/24"
  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# Private Service Access (VPC peering for Cloud SQL private IP)
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "private_ip_range" {
  project       = var.project_id
  name          = "${var.deployment_name}-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_service" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
  deletion_policy         = "ABANDON"
}

# ---------------------------------------------------------------------------
# Firewall: deny all ingress by default, allow internal communication
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "deny_all_ingress" {
  project  = var.project_id
  name     = "${var.deployment_name}-deny-all-ingress"
  network  = google_compute_network.main.id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
}

resource "google_compute_firewall" "allow_internal" {
  project  = var.project_id
  name     = "${var.deployment_name}-allow-internal"
  network  = google_compute_network.main.id
  priority = 1000

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
  direction     = "INGRESS"
}
