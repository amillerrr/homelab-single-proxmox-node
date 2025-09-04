#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TALOS_DIR="${PROJECT_ROOT}/infrastructure/talos"
TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure/opentofu"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_VIP="10.0.10.250"
CP_IPS=("10.0.10.210" "10.0.10.211" "10.0.10.212")
WORKER_IPS=("10.0.10.220" "10.0.10.221" "10.0.10.222")

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}     Talos Kubernetes Cluster Bootstrap        ${NC}"
echo -e "${BLUE}================================================${NC}"

# Step 1: Check prerequisites
echo -e "\n${GREEN}[1/7] Checking prerequisites...${NC}"
command -v talosctl >/dev/null 2>&1 || { echo -e "${RED}talosctl is required but not installed.${NC}" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed.${NC}" >&2; exit 1; }
command -v tofu >/dev/null 2>&1 || { echo -e "${RED}OpenTofu is required but not installed.${NC}" >&2; exit 1; }

# Step 2: Generate configurations if needed
echo -e "\n${GREEN}[2/7] Generating Talos configurations...${NC}"
"${SCRIPT_DIR}/generate-configs.sh"

# Step 3: Deploy infrastructure with OpenTofu
echo -e "\n${GREEN}[3/7] Deploying infrastructure with OpenTofu...${NC}"
cd "${TERRAFORM_DIR}"

echo "Initializing OpenTofu..."
tofu init

echo "Planning infrastructure..."
tofu plan

echo -e "${YELLOW}Ready to deploy infrastructure. Continue? (yes/no)${NC}"
read -r response
if [[ "$response" != "yes" ]]; then
    echo -e "${RED}Deployment cancelled.${NC}"
    exit 1
fi

echo "Applying infrastructure..."
tofu apply -auto-approve

# Step 4: Wait for VMs to be ready
echo -e "\n${GREEN}[4/7] Waiting for VMs to be ready...${NC}"
sleep 30

# Step 5: Apply Talos configurations
echo -e "\n${GREEN}[5/7] Applying Talos configurations...${NC}"

export TALOSCONFIG="${TALOS_DIR}/talosconfig"

# Apply control plane configs
for i in "${!CP_IPS[@]}"; do
    ip="${CP_IPS[$i]}"
    idx=$((i + 1))
    echo "Applying config to control plane node ${idx} (${ip})..."
    
    # Wait for node to be reachable
    until nc -zv "${ip}" 50000 2>/dev/null; do
        echo "Waiting for Talos API on ${ip}..."
        sleep 5
    done
    
    talosctl apply-config \
        --insecure \
        --nodes "${ip}" \
        --file "${TALOS_DIR}/controlplane-${idx}.yaml"
done

# Apply worker configs
for i in "${!WORKER_IPS[@]}"; do
    ip="${WORKER_IPS[$i]}"
    idx=$((i + 1))
    echo "Applying config to worker node ${idx} (${ip})..."
    
    # Wait for node to be reachable
    until nc -zv "${ip}" 50000 2>/dev/null; do
        echo "Waiting for Talos API on ${ip}..."
        sleep 5
    done
    
    talosctl apply-config \
        --insecure \
        --nodes "${ip}" \
        --file "${TALOS_DIR}/worker-${idx}.yaml"
done

# Step 6: Bootstrap the cluster
echo -e "\n${GREEN}[6/7] Bootstrapping Kubernetes cluster...${NC}"
sleep 30

talosctl config endpoint "${CP_IPS[0]}"
talosctl config node "${CP_IPS[0]}"

echo "Running bootstrap..."
talosctl bootstrap

echo "Waiting for cluster to be healthy..."
talosctl health --wait-timeout 10m

# Step 7: Configure kubectl
echo -e "\n${GREEN}[7/7] Configuring kubectl...${NC}"
talosctl kubeconfig "${HOME}/.kube/config"

# Verify cluster
echo -e "\n${GREEN}Verifying cluster...${NC}"
kubectl get nodes

echo -e "\n${BLUE}================================================${NC}"
echo -e "${GREEN}    Cluster bootstrap complete!                ${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Install ArgoCD for GitOps:"
echo "   kubectl create namespace argocd"
echo "   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
echo "2. Get ArgoCD admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo "3. Apply ArgoCD applications:"
echo "   kubectl apply -f clusters/production/argocd/"
echo "4. Check cluster status:"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo "5. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
