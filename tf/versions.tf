terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc10"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.2"
    }
  }
}

# Credentials come from PM_API_URL, PM_USER and PM_PASS in the environment.
provider "proxmox" {
  pm_tls_insecure = var.tls_insecure
}

# The token comes from DIGITALOCEAN_TOKEN in the environment.
provider "digitalocean" {}
