terraform {
  required_version = ">= 1.0"
  
  backend "s3" {
    bucket = "homelab-proxmox-statefile"
    key    = "single-node/k8s-cluster/terraform.tfstate"
    region = "us-west-2"
  }
}

module "talos_cluster" {
  source = "./talos"

  providers = {
    proxmox = proxmox
  }

  image = var.talos_image
  cluster = var.talos_cluster_config
  nodes = var.talos_nodes
}
