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

# Install ArgoCD
install_argocd() {
    log_info "Installing ArgoCD..."
    
    # Add Helm repo
    if ! helm repo add argo https://argoproj.github.io/argo-helm &>/dev/null; then
        log_warn "ArgoCD Helm repo already added"
    fi
    
    helm repo update &>/dev/null
    
    # Install/upgrade ArgoCD
    if ! helm upgrade --install argocd argo/argo-cd \
        --version 8.5.10 \
        --namespace argocd \
        --create-namespace \
        --values clusters/production/infrastructure/argocd/values.yaml \
        --wait \
        --timeout 10m; then
        log_error "Failed to install ArgoCD"
        exit 1
    fi
    
    log_success "ArgoCD installed"
}

# Deploy ApplicationSets
deploy_appprojects() {
   log_info "Deploying ArgoCD AppProjects..."
    
    # Wait for ArgoCD to be ready
    if ! kubectl wait --for=condition=available deployment/argocd-server \
        -n argocd \
        --timeout=120s 2>/dev/null; then
        log_warn "ArgoCD server not fully ready, but continuing..."
    fi
    
    # Apply AppProjects
    local projects=(
        "clusters/production/infrastructure/argocd/appproject-infrastructure.yaml"
        "clusters/production/infrastructure/argocd/appproject-monitoring.yaml"
        "clusters/production/infrastructure/argocd/appproject-platform.yaml"
        "clusters/production/infrastructure/argocd/appproject-applications.yaml"
    )
    
    for project in "${projects[@]}"; do
        if [ -f "$project" ]; then
            if ! kubectl apply -f "$project"; then
                log_error "Failed to apply $project"
                exit 1
            fi
        else
            log_warn "Project file not found: $project (skipping)"
        fi
    done
    
    log_success "AppProjects deployed" 
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
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(secret not found yet)"
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
    install_argocd
    deploy_appprojects
    deploy_root_application
    
    show_next_steps
    show_argocd_credentials
}

# Run main function
main "$@"
