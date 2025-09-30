terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.84.1"
    }
    talos = {
      source = "siderolabs/talos"
      version = "0.9.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
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
  endpoint          = var.proxmox.endpoint
  insecure     = var.proxmox.insecure

  api_token = var.proxmox_api_token
  ssh {
    agent = false
    username = var.proxmox.username
    private_key = file("~/.ssh/proxmox")
  }
}

provider "kubernetes" {
  host = module.talos_cluster.kube_config.kubernetes_client_configuration.host
  client_certificate = base64decode(module.talos_cluster.kube_config.kubernetes_client_configuration.client_certificate)
  client_key = base64decode(module.talos_cluster.kube_config.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(module.talos_cluster.kube_config.kubernetes_client_configuration.ca_certificate)
}
