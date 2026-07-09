variable "project_id" {
  description = "project_id"
  type        = string
}

variable "project_region" {
  description = "project_region"
  type        = string
}

variable "ingress_port" {
  description = "ingress port"
  type        = number
}

variable "service_port" {
  description = "ingress port"
  type        = number
}

variable "network_id" {
  description = "network name"
  type        = string
}

variable "subnets" {
  description = "subnet"
  type        = string
}

variable "ingress_mount_path" {
  description = "subnet"
  type        = string
}

variable "db_instance_name" {
  description = "Base name for the Cloud SQL instance (a random suffix is appended)"
  type        = string
  default     = "orion-pg-dev"
}

variable "db_version" {
  description = "Cloud SQL PostgreSQL database version"
  type        = string
  default     = "POSTGRES_18"
}

variable "db_tier" {
  description = "Machine tier for the Cloud SQL instance (dev-sized by default)"
  type        = string
  default     = "db-f1-micro"
}

variable "db_disk_size_gb" {
  description = "Initial SSD size in GB for the Cloud SQL instance"
  type        = number
  default     = 10
}

variable "db_deletion_protection" {
  description = "Prevent accidental terraform destroy of the SQL instance"
  type        = bool
  default     = false
}

variable "db_backup_enabled" {
  description = "Enable automated backups (cheap safety net even for dev)"
  type        = bool
  default     = true
}

variable "orion_secrets" {
  description = "Sensitive Orion env vars injected from Secret Manager (keys must match app env names)"
  type        = map(string)
  sensitive   = true

  validation {
    condition = alltrue([
      for k in keys(var.orion_secrets) : contains([
        "JWT_SECRET",
        "POSTGRES_PASSWORD",
        "POSTGRES_USER",
        "POSTGRES_DB",
      ], k)
    ])
    error_message = "orion_secrets keys must be a subset of: JWT_SECRET, POSTGRES_PASSWORD, POSTGRES_USER, POSTGRES_DB."
  }

  validation {
    condition = alltrue([
      for k in [
        "JWT_SECRET",
        "POSTGRES_PASSWORD",
        "POSTGRES_USER",
        "POSTGRES_DB",
      ] : contains(keys(var.orion_secrets), k)
    ])
    error_message = "orion_secrets must include JWT_SECRET, POSTGRES_PASSWORD, POSTGRES_USER, and POSTGRES_DB."
  }
}

variable "orion_env" {
  description = "Non-secret Orion env vars injected as plain Cloud Run env (keys must match app env names)"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.orion_env) : contains([
        "POSTGRES_HOST",
        "POSTGRES_PORT",
        "POSTGRES_SSLMODE",
        "PGSSLMODE",
        "JWT_EXPIRY_MINUTES",
        "BCRYPT_COST",
        "AUTH_ENABLED",
      ], k)
    ])
    error_message = "orion_env keys must be a subset of: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_SSLMODE, PGSSLMODE, JWT_EXPIRY_MINUTES, BCRYPT_COST, AUTH_ENABLED."
  }
}
