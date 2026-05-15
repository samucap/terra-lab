terraform {
  required_providers {
    #aws = {
    #  source  = "hashicorp/aws"
    #  version = "~> 6.0"
    #}
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }

    google = {
      source = "hashicorp/google"
      version = "~> 7.26.0"
    }
  }
}

provider "google" {
  project = "notdough"
  region = "us-central1"
}
#provider "aws" {
#  region  = "us-west-2"
#  profile = "fortress" # Your secure profile
#}