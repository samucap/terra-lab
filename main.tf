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

data "google_project" "project" {}

resource "google_secret_manager_secret" "nginx_conf" {
  secret_id = "nginx-conf"
  
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "nginx_conf_data" {
  secret      = google_secret_manager_secret.nginx_conf.id
  secret_data = file("${path.module}/nginx.conf")
}

resource "google_secret_manager_secret_iam_member" "secret_access" {
  secret_id = google_secret_manager_secret.nginx_conf.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_cloud_run_v2_service" "ingress_instance" {
  name                = "ingress-instance"
  location            = "us-west1"
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  depends_on = [google_secret_manager_secret_iam_member.secret_access]

  template {
    health_check_disabled = true

    # Direct VPC egress configuration for the entire service (including sidecar)
    vpc_access {
      network_interfaces {
        network    = "default" # TODO: Replace with your VPC network name
        subnetwork = "default" # TODO: Replace with your subnetwork name
      }
      # PRIVATE_RANGES_ONLY routes only internal IP traffic to the VPC. 
      # ALL_TRAFFIC routes all outbound traffic to the VPC.
      egress = "PRIVATE_RANGES_ONLY" 
    }

    volumes {
      name = "nginx-conf-volume"
      secret {
        secret = google_secret_manager_secret.nginx_conf.secret_id
        items {
          version = "latest"
          path    = "default.conf"
        }
      }
    }

    containers {
      name  = "ingress-instance"
      image = "docker.io/library/nginx:latest"
      ports {
        container_port = 8080
      }

      volume_mounts {
        name       = "nginx-conf-volume"
        mount_path = "/etc/nginx/conf.d"
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
      env {
        name = "PORT"
        value = "8888"
      }
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
