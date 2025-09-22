#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ARGOCD_VERSION="stable"
ARGOCD_NAMESPACE="argocd"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/yourusername/k8s-talos-proxmox}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}         ArgoCD GitOps Setup                   ${NC}"
echo -e "${BLUE}================================================${NC}"

# Check prerequisites
echo -e "\n${GREEN}[1/8] Checking prerequisites...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed.${NC}" >&2; exit 1; }

# Check if cluster is accessible
if ! kubectl get nodes &>/dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Install ArgoCD CLI if not present
echo -e "\n${GREEN}[2/8] Installing ArgoCD CLI...${NC}"
if ! command -v argocd &> /dev/null; then
    echo "Downloading ArgoCD CLI..."
    curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /tmp/argocd
    sudo mv /tmp/argocd /usr/local/bin/argocd
    echo "ArgoCD CLI installed successfully"
else
    echo "ArgoCD CLI already installed: $(argocd version --client --short)"
fi

# Create ArgoCD namespace
echo -e "\n${GREEN}[3/8] Creating ArgoCD namespace...${NC}"
kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo -e "\n${GREEN}[4/8] Installing ArgoCD...${NC}"
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Wait for ArgoCD to be ready
echo -e "\n${GREEN}[5/8] Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n ${ARGOCD_NAMESPACE}
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n ${ARGOCD_NAMESPACE}
kubectl wait --for=condition=available --timeout=600s deployment/argocd-redis -n ${ARGOCD_NAMESPACE}
kubectl wait --for=condition=available --timeout=600s deployment/argocd-dex-server -n ${ARGOCD_NAMESPACE}

# Get initial admin password
echo -e "\n${GREEN}[6/8] Retrieving ArgoCD admin credentials...${NC}"
ARGOCD_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "${YELLOW}ArgoCD Admin Credentials:${NC}"
echo -e "Username: ${GREEN}admin${NC}"
echo -e "Password: ${GREEN}${ARGOCD_PASSWORD}${NC}"
echo -e "${YELLOW}Please save these credentials securely!${NC}"

# Port forward to ArgoCD server
echo -e "\n${GREEN}[7/8] Starting port-forward to ArgoCD server...${NC}"
echo "Starting port-forward in background..."
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443 &>/dev/null &
PF_PID=$!
sleep 5

# Login to ArgoCD
echo -e "\n${GREEN}Logging into ArgoCD...${NC}"
if argocd login localhost:8080 --username admin --password "${ARGOCD_PASSWORD}" --insecure; then
    echo "Successfully logged into ArgoCD"
else
    echo -e "${YELLOW}Could not auto-login to ArgoCD. You may need to login manually.${NC}"
fi

# Update Git repository URL if provided
echo -e "\n${GREEN}[8/8] Configuring ArgoCD applications...${NC}"
echo -e "${YELLOW}Enter your Git repository URL (or press Enter to use: ${GITHUB_REPO_URL}):${NC}"
read -r custom_repo_url
if [ -n "$custom_repo_url" ]; then
    GITHUB_REPO_URL="$custom_repo_url"
fi

# Create ArgoCD application manifests with the correct repo URL
cat > /tmp/argocd-apps.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: ${ARGOCD_NAMESPACE}
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITHUB_REPO_URL}
    targetRevision: ${GITHUB_BRANCH}
    path: clusters/production/infrastructure
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: applications
  namespace: ${ARGOCD_NAMESPACE}
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITHUB_REPO_URL}
    targetRevision: ${GITHUB_BRANCH}
    path: clusters/production/apps
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# Apply ArgoCD applications
echo -e "${YELLOW}Ready to create ArgoCD applications. Continue? (yes/no)${NC}"
read -r response
if [[ "$response" == "yes" ]]; then
    kubectl apply -f /tmp/argocd-apps.yaml
    echo -e "${GREEN}ArgoCD applications created successfully!${NC}"
    
    # Trigger initial sync
    echo "Triggering initial sync..."
    argocd app sync infrastructure
    argocd app sync applications
else
    echo -e "${YELLOW}Skipping ArgoCD application creation.${NC}"
    echo "You can apply them later with:"
    echo "  kubectl apply -f clusters/production/argocd/"
fi

# Clean up
rm -f /tmp/argocd-apps.yaml

# Stop port-forward
kill $PF_PID 2>/dev/null || true

echo -e "\n${BLUE}================================================${NC}"
echo -e "${GREEN}       ArgoCD Setup Complete!                  ${NC}"
echo -e "${BLUE}================================================${NC}"

echo -e "\n${YELLOW}Access ArgoCD:${NC}"
echo "1. Port forward:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "2. Open browser:"
echo "   https://localhost:8080"
echo ""
echo "3. Login:"
echo "   Username: admin"
echo "   Password: ${ARGOCD_PASSWORD}"
echo ""
echo -e "${YELLOW}CLI Access:${NC}"
echo "   argocd login localhost:8080 --username admin --password '${ARGOCD_PASSWORD}' --insecure"
echo "   argocd app list"
echo "   argocd app sync <app-name>"
echo ""
echo -e "${YELLOW}Update password:${NC}"
echo "   argocd account update-password"
echo ""
echo -e "${GREEN}Happy GitOps!${NC}"
