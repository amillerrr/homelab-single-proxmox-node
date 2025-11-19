# Install ArgoCD via Helm
resource "helm_release" "argocd" {
  depends_on = [module.talos_cluster]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6" # Pinned for stability

  # Reuse your existing GitOps values file
  values = [
    file("${path.module}/../../clusters/production/infrastructure/controllers/argocd/values.yaml")
  ]
  
  # Wait for CRDs to be established
  wait = true
  timeout = 600
}

# Apply the Root Application (App of AppSets)
# This triggers the deployment of everything else in the 'clusters' directory
resource "kubernetes_manifest" "bootstrap_app" {
  depends_on = [helm_release.argocd]

  manifest = yamldecode(file("${path.module}/../../clusters/production/bootstrap/argocd-app-of-appsets.yaml"))
}
