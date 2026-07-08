# Uncomment and configure after creating the GCS bucket:
#   gsutil mb -p YOUR_PROJECT -l us-west2 -b on gs://YOUR_BUCKET
#   gsutil versioning set on gs://YOUR_BUCKET
#
# terraform {
#   backend "gcs" {
#     bucket = "YOUR_BUCKET"
#     prefix = "terraform/go-api"
#   }
# }
