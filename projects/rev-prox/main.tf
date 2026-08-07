data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "nginx" {
  name        = "fortress-nginx-sg"
  description = "HTTPS only"
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "nginx" {
  name = "fortress-nginx-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_instance_profile" "nginx" {
  name = "fortress-nginx-profile"
  role = aws_iam_role.nginx.name
}

resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.nginx.name
  security_groups             = [aws_security_group.nginx.name]
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    apt update -y && apt install -y nginx certbot python3-certbot-nginx
    systemctl enable nginx
    # For verify: Comment Certbot if no domain; use self-signed below
    # certbot --nginx -d yourdomain.com --non-interactive --agree-tos --email your@email.com
    cat > /etc/nginx/sites-available/reverse <<EOC
    server {
      listen 443 ssl;
      server_name _;  # Wildcard for verify
      # Self-signed for quick test (replace with Certbot paths in prod)
      ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
      ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

      location / {
        proxy_pass ${var.backend_target};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      }

      limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
      limit_req zone=one burst=20 nodelay;
    }
    EOC
    # Quick self-signed cert gen
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj "/CN=localhost"
    ln -s /etc/nginx/sites-available/reverse /etc/nginx/sites-enabled/
    rm /etc/nginx/sites-enabled/default
    nginx -t && systemctl restart nginx
  EOF

  tags = { Name = "fortress-nginx-verify" }
}
