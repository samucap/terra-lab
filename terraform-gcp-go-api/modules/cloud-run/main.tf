variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "deployment_name" {
  type = string
}

variable "container_image" {
  type = string
}

variable "service_account_email" {
  type = string
}

variable "network_name" {
  type        = string
  description = "VPC network name for Direct VPC Egress."
}

variable "subnet_name" {
  type        = string
  description = "Subnet name for Direct VPC Egress."
}

variable "db_private_ip" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_connection_name" {
  type = string
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 10
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "concurrency" {
  type    = number
  default = 100
}

variable "labels" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Cloud Run v2 service with Direct VPC Egress (no VPC Connector)
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "api" {
  project  = var.project_id
  name     = "${var.deployment_name}-api"
  location = var.region

  # Only accept traffic from the Global LB and internal sources.
  # This forces all external traffic through Cloud Armor.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = var.service_account_email
    labels          = var.labels

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    max_instance_request_concurrency = var.concurrency

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "DB_HOST"
        value = var.db_private_ip
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = var.db_connection_name
      }

      startup_probe {
        http_get {
          path = "/"
        }
        initial_delay_seconds = 0
        period_seconds        = 10
        failure_threshold     = 3
        timeout_seconds       = 3
      }

      liveness_probe {
        http_get {
          path = "/"
        }
        period_seconds    = 30
        failure_threshold = 3
        timeout_seconds   = 3
      }
    }

    # Direct VPC Egress — connects Cloud Run directly to the VPC subnet
    # without a Serverless VPC Access connector. Lower latency, no extra
    # resource cost, and the 2026-recommended approach.
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"

      network_interfaces {
        network    = var.network_name
        subnetwork = var.subnet_name
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Allow unauthenticated invocations — authentication is enforced at the
# Global LB / Cloud Armor layer, not at the Cloud Run service level.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
