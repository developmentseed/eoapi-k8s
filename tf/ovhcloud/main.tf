terraform {
  required_version = ">= 1.7.4"

  # you need to pass this on
  # `tofu init -backend-config=./backend-configs/<name>.tfbackend`
  backend "s3" {}

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.48"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "ovh" {
  endpoint = var.ovh_endpoint
}

# Get available regions
data "ovh_cloud_project_regions" "available" {
  service_name = var.ovh_service_name
  has_services_up = ["kubernetes"]
}

# Get available Kubernetes versions
data "ovh_cloud_project_kube_versions" "available" {
  service_name = var.ovh_service_name
}