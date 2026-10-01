terraform {
  required_version = ">= 1.11.1"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2"
    }
  }
}
