# GCP Go API — Serverless Terraform Stack

Production-ready, cost-optimized GCP backend: **Cloud Run v2** (Go) + **Cloud SQL** (PostgreSQL, private IP, IAM auth) + **Global HTTPS LB** + **Cloud Armor WAF**, connected via **Direct VPC Egress** in a custom VPC.

```
Internet → Cloud Armor (WAF) → Global HTTPS LB → Serverless NEG → Cloud Run v2
                                                                        │
                                                              Direct VPC Egress
                                                                        │
                                                              Cloud SQL (private IP)
```

## Architecture

| Component | Resource | Key Config |
|---|---|---|
| Networking | Custom VPC + /24 subnet | us-west2, private service access |
| Database | Cloud SQL PostgreSQL 16 | db-f1-micro, private IP only, IAM auth |
| Compute | Cloud Run v2 | Scale-to-zero, Direct VPC Egress, LB-only ingress |
| Edge | Global External HTTPS LB | Serverless NEG, Google-managed SSL (free) |
| Security | Cloud Armor | OWASP WAF rules, rate limiting, adaptive DDoS |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.14
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated (`gcloud auth application-default login`)
- A GCP project with billing enabled
- A domain name with DNS access (for the SSL certificate)

## Quick Start

```bash
cd terraform-gcp-go-api

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id, domain_name, container_image

# 2. Deploy
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan

# 3. Point DNS
# Create an A record for your domain -> the load_balancer_ip output
# SSL provisioning takes 15-30 min after DNS propagates

# 4. Verify (after DNS propagation + SSL provisioning)
curl -v "https://YOUR_DOMAIN/"
# Or test immediately against the IP (skip cert check):
# curl -kv "https://$(terraform output -raw load_balancer_ip)/"
```

## Remote State (Optional)

Create a GCS bucket for encrypted remote state:

```bash
PROJECT_ID="your-project"
BUCKET="${PROJECT_ID}-tfstate"

gsutil mb -p "$PROJECT_ID" -l us-west2 -b on "gs://${BUCKET}"
gsutil versioning set on "gs://${BUCKET}"
```

Then uncomment and fill in `backend.tf`.

## Cost Estimate (Low Traffic)

| Resource | Monthly Cost | Notes |
|---|---|---|
| Cloud SQL db-f1-micro | ~$9.37 | Always-on, shared-core, 10 GB SSD |
| Cloud Run | ~$0–2 | Scale-to-zero, pay per request |
| Global LB forwarding rules | ~$18 | 2 rules (HTTPS + HTTP redirect) @ $0.025/hr |
| Cloud Armor | ~$5 | Policy base + per-rule pricing |
| Google-managed SSL | Free | |
| GCS state bucket | ~$0.02 | |
| **Total** | **~$32–35/mo** | At near-zero traffic |

### Hitting $25/mo or Less

The Global LB forwarding rules are the price floor (~$18/mo). To go lower:

1. **Skip the LB + Cloud Armor** — use Cloud Run's built-in HTTPS URL directly. You lose WAF protection but save ~$23/mo, bringing the total to ~$9–12/mo.
2. **Use Cloud Run's `ingress = "INGRESS_TRAFFIC_ALL"`** and handle rate limiting in your Go code or via a middleware.

The LB module can be commented out in `main.tf` and re-enabled later.

## Direct VPC Egress — Why Not VPC Connector?

| | Direct VPC Egress | Serverless VPC Access Connector |
|---|---|---|
| Extra resource | None | e2-micro instances (min 2) |
| Cost | $0 (included) | ~$7/mo minimum |
| Latency | Lower (direct NIC) | Higher (extra hop) |
| Max throughput | 1 Gbps/instance | 300–1000 Mbps |
| GCP recommendation (2026) | Yes | Legacy |

Direct VPC Egress attaches a network interface directly to Cloud Run instances, connecting them to your VPC subnet with no intermediary. It is the 2026-recommended approach and eliminates the cost and operational overhead of VPC Connectors.

## Security Checklist

- [x] **Private-only database** — Cloud SQL has no public IP; accessible only via VPC peering
- [x] **IAM database auth** — No passwords; Cloud Run SA authenticates via `CLOUD_IAM_SERVICE_ACCOUNT`
- [x] **LB-only ingress** — Cloud Run rejects traffic not from the Global LB or internal sources
- [x] **Cloud Armor WAF** — SQLi, XSS, LFI, RFI, RCE, scanner detection rules (OWASP v3.3)
- [x] **Rate limiting** — 100 req/min per IP with 5-minute ban on exceed
- [x] **Adaptive DDoS** — Layer-7 ML-based attack detection enabled
- [x] **HTTPS everywhere** — HTTP auto-redirects to HTTPS; Google-managed TLS cert
- [x] **Least privilege IAM** — Cloud Run SA has only `cloudsql.instanceUser` + `cloudsql.client`
- [x] **Deletion protection** — Cloud SQL has `deletion_protection = true`
- [x] **Deny-all firewall** — VPC denies all ingress by default; internal traffic explicitly allowed
- [x] **Encrypted state** — GCS backend with versioning (CMEK optional)

## File Structure

```
terraform-gcp-go-api/
├── main.tf                      # Module composition, service account, API enablement
├── providers.tf                 # Terraform + Google provider versions
├── variables.tf                 # All input variables with defaults
├── outputs.tf                   # LB IP, Cloud Run URI, Cloud SQL connection info
├── backend.tf                   # GCS remote state (template)
├── terraform.tfvars.example     # Example variable values
├── README.md
└── modules/
    ├── vpc/
    │   ├── main.tf              # Custom VPC, subnet, private service access, firewalls
    │   └── outputs.tf
    ├── cloud-sql/
    │   ├── main.tf              # PostgreSQL 16, db-f1-micro, private IP, IAM auth
    │   └── outputs.tf
    ├── cloud-run/
    │   ├── main.tf              # Cloud Run v2, Direct VPC Egress, scale-to-zero
    │   └── outputs.tf
    └── load-balancer/
        ├── main.tf              # Global HTTPS LB, Serverless NEG, Cloud Armor
        └── outputs.tf
```

## Cloud Build Trigger (Optional)

Example `cloudbuild.yaml` for automatic deploys on push:

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA', '.']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA']
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'services'
      - 'update'
      - '${_SERVICE_NAME}'
      - '--image=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_IMAGE}:$SHORT_SHA'
      - '--region=${_REGION}'
substitutions:
  _REGION: us-west2
  _REPO: api
  _IMAGE: go-api
  _SERVICE_NAME: go-api-api
```

## Useful Commands

```bash
# Validate config
terraform validate

# Preview changes
terraform plan

# Apply
terraform apply

# Show outputs
terraform output

# Destroy (will fail until you disable Cloud SQL deletion protection)
# gcloud sql instances patch $(terraform output -raw cloud_sql_connection_name | cut -d: -f3) --no-deletion-protection
terraform destroy

# Test Cloud Armor rules
curl -v "https://your-domain.com/?id=1'+OR+'1'='1"   # Should return 403
curl -v "https://your-domain.com/"                     # Should return 200

# View Cloud Armor logs
gcloud logging read \
  "resource.type=http_load_balancer AND jsonPayload.enforcedSecurityPolicy.name=go-api-armor" \
  --project=YOUR_PROJECT --limit=10 --format=json
```

---

Built for @sammmpark's GCP serverless stack. Cloud Run v2 + Direct VPC Egress + Cloud Armor — the 2026 way to ship a Go API on GCP without burning money.

### X Post Template

> Shipped a production Go API on GCP for ~$10/mo (without LB) or ~$33/mo (full WAF stack):
>
> - Cloud Run v2 with Direct VPC Egress (no VPC Connector)
> - Cloud SQL PostgreSQL with IAM auth (no passwords)
> - Global HTTPS LB + Cloud Armor (OWASP + rate limiting)
> - Scale-to-zero everything
>
> Entire infra is 12 Terraform files. Open source soon.
> #GCP #Terraform #CloudRun #GoLang
