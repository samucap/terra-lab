data "google_project" "project" {}

#TODO:
# - resource for vpc network and subnets, along with firewall rules
# - resource for gcloud run for sync script
# Cloud SQL: see sql.tf (private IP on var.network_id)

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

resource "google_cloud_run_v2_service" "api_service" {
  name     = "api-service"
  location = "us-west1"
  //TODO: change to private
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  depends_on = [
    google_secret_manager_secret_iam_member.secret_access,
    google_secret_manager_secret_iam_member.orion_accessor,
  ]

  template {
    health_check_disabled = true

    # Direct VPC egress configuration for the entire service (including sidecar)
    vpc_access {
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnets
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
        container_port = var.ingress_port
      }

      volume_mounts {
        name       = "nginx-conf-volume"
        mount_path = var.ingress_mount_path
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
      image = "us-west1-docker.pkg.dev/notable-dough/orion/orion2.0:v1"

      env {
        name  = "PORT"
        value = var.service_port
      }

      # POSTGRES_HOST always comes from the Cloud SQL private IP.
      # Other keys (POSTGRES_PORT, POSTGRES_SSLMODE, etc.) come from orion_env / tfvars.
      dynamic "env" {
        for_each = merge(
          var.orion_env,
          {
            POSTGRES_HOST = google_sql_database_instance.postgres.private_ip_address
            POSTGRES_PORT = lookup(var.orion_env, "POSTGRES_PORT", "5432")
          },
        )
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = google_secret_manager_secret.orion
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }
}

#TODO: changethis to private access from specific origin ip only
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.api_service.project
  location = google_cloud_run_v2_service.api_service.location
  name     = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Output the public URL of your Nginx server
output "nginx_url" {
  value       = google_cloud_run_v2_service.api_service.uri
  description = "The public URL of the deployed Nginx web server"
}
