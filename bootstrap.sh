#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  local missing_tools=()
  
  if ! command -v kubectl &> /dev/null; then
      missing_tools+=("kubectl")
  fi
  
  if ! command -v helm &> /dev/null; then
      missing_tools+=("helm")
  fi
  
  if [ ${#missing_tools[@]} -ne 0 ]; then
      log_error "Missing required tools: ${missing_tools[*]}"
      log_info "Install them and try again"
      exit 1
  fi
  
  log_success "Prerequisites satisfied"
}

# Wait for cluster to be ready
wait_for_cluster() {
  log_info "Waiting for cluster to be ready..."
  
  if ! kubectl wait --for=condition=ready nodes --all --timeout=300s 2>/dev/null; then
      log_error "Cluster nodes did not become ready in time"
      exit 1
  fi
  
  log_success "Cluster is ready"
}

# Wait for Cilium to be ready
wait_for_cilium() {
  log_info "Waiting for Cilium CNI to be ready..."
  
  # Wait for Cilium pods
  if ! kubectl wait --for=condition=ready pod \
      -n kube-system \
      -l k8s-app=cilium \
      --timeout=300s 2>/dev/null; then
      log_error "Cilium pods did not become ready"
      exit 1
  fi
  
  log_success "Cilium is ready"
}

# Label worker nodes
label_worker_nodes() {
  log_info "Labeling worker nodes..."
  
  local labeled=0
  
  for node in $(kubectl get nodes -o name | grep -E 'wk-[0-9]+$' | sed 's|node/||'); do
      if kubectl label node "$node" node-role.kubernetes.io/worker=true --overwrite 2>/dev/null; then
          log_success "Labeled: $node"
          ((labeled++))
      fi
  done
  
  if [ $labeled -eq 0 ]; then
      log_warn "No worker nodes found matching pattern 'wk-*'"
  else
      log_success "Labeled $labeled worker node(s)"
  fi
}

# Install ArgoCD
install_argocd() {
  log_info "Bootstrapping ArgoCD from Git..."
    
  # Create the namespace first
  if ! kubectl get namespace argocd &>/dev/null; then
      kubectl create namespace argocd
  fi
  
  if ! kubectl kustomize clusters/production/infrastructure/controllers/argocd/ --enable-helm | kubectl apply -f -; then
      log_error "Failed to apply ArgoCD Kustomization"
      exit 1
  fi

  log_info "Waiting for ArgoCD server to be ready..."
  if ! kubectl wait --for=condition=available deployment/argocd-server \
      -n argocd \
      --timeout=5m; then
      log_error "ArgoCD server did not become available in time"
      exit 1
  fi
  
  log_success "ArgoCD bootstrapped"
}

# Deploy root Application (App of AppSets)
deploy_root_application() {
  log_info "Deploying root Application (App of AppSets)..."
  
  # Give ArgoCD a moment to settle
  sleep 5
  
  # Apply the root application
  if ! kubectl apply -f clusters/production/bootstrap/argocd-app-of-appsets.yaml; then
      log_error "Failed to apply root Application"
      exit 1
  fi
  
  log_success "Root Application deployed"
  log_info "ArgoCD is now self-managing"
}

# Get ArgoCD credentials
show_argocd_credentials() {
  echo ""
  log_info "ArgoCD Credentials:"
  echo "  Username: admin"
  echo -n "  Password: "
  kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d && echo
  echo ""
  echo ""
  log_info "Access ArgoCD:"
  echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
  echo "  Then visit: https://localhost:8080"
  echo ""
}

# Summarize next steps
show_next_steps() {
  echo ""
  log_success "Bootstrap complete!"
  echo ""
  log_info "Monitor progress:"
  echo "  kubectl get applications -n argocd -w"
  echo ""
  log_info "View ApplicationSets:"
  echo "  kubectl get applicationsets -n argocd"
  echo ""
  log_info "Check a specific application:"
  echo "  kubectl describe application <name> -n argocd"
  echo ""
}

# Main execution
main() {
  echo ""
  log_info "Starting Kubernetes Cluster Bootstrap (Stage 2)"
  echo ""
  
  check_prerequisites
  wait_for_cluster
  wait_for_cilium
  label_worker_nodes
  install_argocd
  deploy_root_application
  
  show_next_steps
  show_argocd_credentials
}

# Run main function
main "$@"
