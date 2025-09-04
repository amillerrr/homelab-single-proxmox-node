terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Provider configuration
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_tls_insecure     = var.proxmox_tls_insecure
  pm_parallel         = 3
  pm_timeout          = 600
  pm_debug            = false
}
