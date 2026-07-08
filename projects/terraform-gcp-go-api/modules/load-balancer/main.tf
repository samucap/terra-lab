variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "deployment_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "cloud_run_service_name" {
  type = string
}

variable "rate_limit_per_minute" {
  type    = number
  default = 100
}

variable "labels" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Static external IP for the Global LB
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "${var.deployment_name}-lb-ip"
}

# ---------------------------------------------------------------------------
# Serverless NEG -> Cloud Run
# ---------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "cloud_run" {
  project               = var.project_id
  name                  = "${var.deployment_name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = var.cloud_run_service_name
  }
}

# ---------------------------------------------------------------------------
# Backend service (connects LB to NEG, attaches Cloud Armor)
# ---------------------------------------------------------------------------

resource "google_compute_backend_service" "api" {
  project     = var.project_id
  name        = "${var.deployment_name}-backend"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  security_policy = google_compute_security_policy.armor.id

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ---------------------------------------------------------------------------
# URL map — pass-through, all paths forwarded unchanged
# ---------------------------------------------------------------------------

resource "google_compute_url_map" "main" {
  project         = var.project_id
  name            = "${var.deployment_name}-url-map"
  default_service = google_compute_backend_service.api.id
}

# ---------------------------------------------------------------------------
# Google-managed SSL certificate (free)
# ---------------------------------------------------------------------------

resource "google_compute_managed_ssl_certificate" "main" {
  project = var.project_id
  name    = "${var.deployment_name}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }
}

# ---------------------------------------------------------------------------
# HTTPS frontend (port 443)
# ---------------------------------------------------------------------------

resource "google_compute_target_https_proxy" "main" {
  project          = var.project_id
  name             = "${var.deployment_name}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  project    = var.project_id
  name       = "${var.deployment_name}-https-rule"
  target     = google_compute_target_https_proxy.main.id
  port_range = "443"
  ip_address = google_compute_global_address.lb.address
  labels     = var.labels
}

# ---------------------------------------------------------------------------
# HTTP -> HTTPS redirect (port 80)
# ---------------------------------------------------------------------------

resource "google_compute_url_map" "http_redirect" {
  project = var.project_id
  name    = "${var.deployment_name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "${var.deployment_name}-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  project    = var.project_id
  name       = "${var.deployment_name}-http-redirect-rule"
  target     = google_compute_target_http_proxy.redirect.id
  port_range = "80"
  ip_address = google_compute_global_address.lb.address
  labels     = var.labels
}

# ===========================================================================
# Cloud Armor security policy
# ===========================================================================

resource "google_compute_security_policy" "armor" {
  project = var.project_id
  name    = "${var.deployment_name}-armor"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }

  # ---- OWASP Top-10 preconfigured WAF rules ----

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQL injection"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS"
  }

  rule {
    action   = "deny(403)"
    priority = 1002
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable')"
      }
    }
    description = "Block local file inclusion"
  }

  rule {
    action   = "deny(403)"
    priority = 1003
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-v33-stable')"
      }
    }
    description = "Block remote file inclusion"
  }

  rule {
    action   = "deny(403)"
    priority = 1004
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-v33-stable')"
      }
    }
    description = "Block remote code execution"
  }

  rule {
    action   = "deny(403)"
    priority = 1005
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('scannerdetection-v33-stable')"
      }
    }
    description = "Block vulnerability scanners"
  }

  # ---- Rate limiting ----

  rule {
    action   = "rate_based_ban"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = var.rate_limit_per_minute
        interval_sec = 60
      }
      ban_duration_sec = 300
      enforce_on_key   = "IP"
    }
    description = "Rate limit per IP, ban on exceed"
  }

  # ---- Default allow ----

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}
