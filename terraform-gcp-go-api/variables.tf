variable "project_id" {
  type        = string
  description = "GCP project ID to deploy into."
}

variable "region" {
  type        = string
  description = "GCP region for all regional resources."
  default     = "us-west2"
}

variable "zone" {
  type        = string
  description = "GCP zone for zonal resources (Cloud SQL)."
  default     = "us-west2-a"
}

variable "deployment_name" {
  type        = string
  description = "Prefix applied to all resource names."
  default     = "go-api"
}

variable "domain_name" {
  type        = string
  description = "Custom domain for the Google-managed SSL certificate (e.g. api.example.com)."
}

variable "container_image" {
  type        = string
  description = "Container image for the Go API Cloud Run service."
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine tier."
  default     = "db-f1-micro"
}

variable "db_version" {
  type        = string
  description = "Cloud SQL PostgreSQL version."
  default     = "POSTGRES_16"
}

variable "db_name" {
  type        = string
  description = "Name of the PostgreSQL database to create."
  default     = "api"
}

variable "cloud_run_min_instances" {
  type        = number
  description = "Minimum Cloud Run instances (0 = scale to zero)."
  default     = 0
}

variable "cloud_run_max_instances" {
  type        = number
  description = "Maximum Cloud Run instances."
  default     = 10
}

variable "cloud_run_cpu" {
  type        = string
  description = "CPU allocation per Cloud Run instance."
  default     = "1"
}

variable "cloud_run_memory" {
  type        = string
  description = "Memory allocation per Cloud Run instance."
  default     = "512Mi"
}

variable "cloud_run_concurrency" {
  type        = number
  description = "Max concurrent requests per Cloud Run instance."
  default     = 100
}

variable "cloud_armor_rate_limit" {
  type        = number
  description = "Cloud Armor rate limit: max requests per minute per IP."
  default     = 100
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to all resources."
  default = {
    managed-by = "terraform"
    stack      = "go-api"
  }
}
