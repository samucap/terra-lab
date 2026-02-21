terraform {
  required_providers {
    # The 'null' provider is a utility that allows us to run specific
    # actions (scripts) without creating a physical resource.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    # The 'local' provider allows Terraform to manage files on your Mac.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

# We do not need to configure the provider blocks with regions/keys
# because these local providers do not require authentication APIs.
provider "null" {}
provider "local" {}
