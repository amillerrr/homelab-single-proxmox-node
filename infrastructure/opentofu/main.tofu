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

resource "helm_release" "argocd" {
  provider = helm.talos 

  # Depend on the *entire module* to ensure cluster is ready
  depends_on = [module.talos_cluster]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.5.10" # From your old job
  namespace        = "argocd"
  create_namespace = true

  values = [
    file("${path.root}/../../clusters/production/infrastructure/argocd/values.yaml")
  ]

  wait_for_jobs = true
}

resource "kubernetes_manifest" "appset_cluster_components" {
  provider = kubernetes.talos 

  # Depend on the Helm release being finished
  depends_on = [helm_release.argocd]
  manifest   = yamldecode(file("${path.root}/../../clusters/production/bootstrap/appset-cluster-components.yaml"))
}

resource "kubernetes_manifest" "appset_no_prune" {
  provider = kubernetes.talos 

  depends_on = [helm_release.argocd]
  manifest   = yamldecode(file("${path.root}/../../clusters/production/bootstrap/appset-cluster-components-no-prune.yaml"))
}
