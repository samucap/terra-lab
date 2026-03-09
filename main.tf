# Secret rotation (GCIH Preparation — optional for verify, but included)
resource "time_rotating" "key_rotation" {
  rotation_days = 1
}

# Example IAM for a service (stub for your Lambda/backend later)
resource "aws_iam_user" "service" {
  name = "fortress-service"
}

resource "aws_iam_access_key" "rotating" {
  user = aws_iam_user.service.name
  lifecycle {
    replace_triggered_by  = [time_rotating.key_rotation.id]
    create_before_destroy = true
  }
}

# Reverse Proxy Module Call
module "reverse_proxy" {
  source         = "./modules/rev-prox"
  backend_target = "http://your-backend-internal:8080" # Placeholder; update for verify (e.g., echo server)
}

# Outputs
output "nginx_public_ip" {
  value = module.reverse_proxy.nginx_public_ip
}
