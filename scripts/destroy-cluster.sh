#!/bin/bash
# destroy-cluster.sh - Destroy the Talos Kubernetes cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure/opentofu"
TALOS_DIR="${PROJECT_ROOT}/infrastructure/talos"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}================================================${NC}"
echo -e "${RED}     WARNING: CLUSTER DESTRUCTION              ${NC}"
echo -e "${RED}================================================${NC}"
echo -e "${YELLOW}This will permanently destroy:${NC}"
echo "  - All Kubernetes workloads"
echo "  - All Proxmox VMs for the cluster"
echo "  - All associated storage"
echo ""
echo -e "${RED}This action cannot be undone!${NC}"
echo ""
echo -e "${YELLOW}Type 'DESTROY' to confirm:${NC}"
read -r response

if [[ "$response" != "DESTROY" ]]; then
    echo "Destruction cancelled."
    exit 0
fi

echo -e "\n${YELLOW}Destroying infrastructure with OpenTofu...${NC}"
cd "${TERRAFORM_DIR}"
tofu destroy -auto-approve

echo -e "\n${YELLOW}Cleaning up configuration files...${NC}"
echo "Keep secrets for potential recovery? (yes/no)"
read -r keep_secrets

if [[ "$keep_secrets" != "yes" ]]; then
    rm -rf "${TALOS_DIR}/secrets"
    echo "Secrets deleted."
else
    echo "Secrets preserved in ${TALOS_DIR}/secrets"
fi

# Clean up generated configs
rm -f "${TALOS_DIR}"/controlplane-*.yaml
rm -f "${TALOS_DIR}"/worker-*.yaml
rm -f "${TALOS_DIR}"/talosconfig

echo -e "\n${RED}Cluster destroyed successfully.${NC}"
