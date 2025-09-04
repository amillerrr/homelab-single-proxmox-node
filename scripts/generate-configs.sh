#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="${SCRIPT_DIR}/../infrastructure/talos"
SECRETS_DIR="${TALOS_DIR}/secrets"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Generating Talos configurations...${NC}"

# Create directories if they don't exist
mkdir -p "${SECRETS_DIR}"

# Configuration variables (update these to match your network)
CLUSTER_NAME="talos-k8s"
CLUSTER_VIP="10.0.10.250"
GATEWAY="10.0.10.1"

# Control plane IPs
CP_IPS=("10.0.10.210" "10.0.10.211" "10.0.10.212")

# Worker IPs
WORKER_IPS=("10.0.10.220" "10.0.10.221" "10.0.10.222")

# Generate secrets if not exists
if [ ! -f "${SECRETS_DIR}/secrets.yaml" ]; then
    echo -e "${YELLOW}Generating new secrets...${NC}"
    talosctl gen secrets -o "${SECRETS_DIR}/secrets.yaml"
else
    echo -e "${YELLOW}Using existing secrets...${NC}"
fi

# Generate base configuration
echo -e "${GREEN}Generating base configuration...${NC}"
talosctl gen config "${CLUSTER_NAME}" "https://${CLUSTER_VIP}:6443" \
    --with-secrets "${SECRETS_DIR}/secrets.yaml" \
    --output-dir "${TALOS_DIR}"

# Generate individual control plane configs with static IPs
echo -e "${GREEN}Generating control plane configurations...${NC}"
for i in "${!CP_IPS[@]}"; do
    ip="${CP_IPS[$i]}"
    idx=$((i + 1))
    
    echo "  - Control Plane ${idx}: ${ip}"
    
    cat > "${TALOS_DIR}/patch-cp-${idx}.yaml" <<EOF
machine:
  network:
    hostname: talos-cp-$(printf "%02d" ${idx})
    interfaces:
      - interface: eth0
        addresses:
          - ${ip}/24
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
        vip:
          ip: ${CLUSTER_VIP}
  kubelet:
    extraArgs:
      rotate-server-certificates: true
cluster:
  apiServer:
    certSANs:
      - ${CLUSTER_VIP}
      - ${ip}
  controlPlane:
    endpoint: https://${CLUSTER_VIP}:6443
EOF
    
    talosctl machineconfig patch "${TALOS_DIR}/controlplane.yaml" \
        --patch @"${TALOS_DIR}/patch-cp-${idx}.yaml" \
        --output "${TALOS_DIR}/controlplane-${idx}.yaml"
done

# Generate individual worker configs with static IPs
echo -e "${GREEN}Generating worker configurations...${NC}"
for i in "${!WORKER_IPS[@]}"; do
    ip="${WORKER_IPS[$i]}"
    idx=$((i + 1))
    
    echo "  - Worker ${idx}: ${ip}"
    
    cat > "${TALOS_DIR}/patch-worker-${idx}.yaml" <<EOF
machine:
  network:
    hostname: talos-worker-$(printf "%02d" ${idx})
    interfaces:
      - interface: eth0
        addresses:
          - ${ip}/24
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
  kubelet:
    extraArgs:
      rotate-server-certificates: true
EOF
    
    talosctl machineconfig patch "${TALOS_DIR}/worker.yaml" \
        --patch @"${TALOS_DIR}/patch-worker-${idx}.yaml" \
        --output "${TALOS_DIR}/worker-${idx}.yaml"
done

# Clean up temporary patch files
rm -f "${TALOS_DIR}"/patch-*.yaml

echo -e "${GREEN}Configuration generation complete!${NC}"
echo -e "${YELLOW}Configurations saved in: ${TALOS_DIR}${NC}"
