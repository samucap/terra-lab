terraform {
  required_version = ">= 1.15.3"
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


