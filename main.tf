terraform {
  required_providers {
    google = {
      source  = "registry.terraform.io/hashicorp/google"
      version = "7.38.0"
    }
  }
}

provider "google" {
  project = "notable-dough"
  region  = "us-west1"
}

resource "google_cloud_run_v2_service" "ingress_instance" {
  name                = "ingress-instance"
  location            = "us-west1"
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    health_check_disabled = true
    containers {
      name  = "ingress-instance"
      image = "docker.io/library/nginx:latest" # Official Nginx image
      ports {
        container_port = 8080 # Forces Cloud Run to route traffic to Nginx's port 80
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi" # Fits standard stateless Nginx proxying workloads
        }
      }
    }

    containers {
      name  = "charon-instance"
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
}

# Allow public (unauthenticated) access to the Nginx service
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.ingress_instance.project
  location = google_cloud_run_v2_service.ingress_instance.location
  name     = google_cloud_run_v2_service.ingress_instance.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Output the public URL of your Nginx server
output "nginx_url" {
  value       = google_cloud_run_v2_service.ingress_instance.uri
  description = "The public URL of the deployed Nginx web server"
}
