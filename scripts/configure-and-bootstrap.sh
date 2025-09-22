#!/bin/bash
# configure-and-bootstrap.sh - Single orchestration script for Talos cluster
# Called by Terraform/OpenTofu after VM creation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="${TALOS_DIR:-${SCRIPT_DIR}/../infrastructure/talos}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CP_IPS=("10.0.70.70" "10.0.70.71" "10.0.70.72")
WORKER_IPS=("10.0.70.80" "10.0.70.81" "10.0.70.82")
CLUSTER_VIP="10.0.70.250"

echo -e "${BLUE}=== Talos Cluster Configuration & Bootstrap ===${NC}"
echo "Script directory: ${SCRIPT_DIR}"
echo "Talos directory: ${TALOS_DIR}"

# Step 1: Generate Talos configurations
echo -e "\n${YELLOW}[Step 1/6] Generating Talos configurations...${NC}"
if [ -f "${SCRIPT_DIR}/generate-configs.sh" ]; then
    "${SCRIPT_DIR}/generate-configs.sh"
else
    echo -e "${RED}No config generation script found!${NC}"
    exit 1
fi

# Step 2: Wait for VMs to fully boot Talos
echo -e "\n${YELLOW}[Step 2/6] Waiting for Talos to boot on VMs...${NC}"
echo "Waiting 90 seconds for Talos to initialize..."
sleep 90

# Step 3: Find and configure nodes
echo -e "\n${YELLOW}[Step 3/6] Finding and configuring Talos nodes...${NC}"

# Find all Talos nodes
NODES=()
for i in {1..69}; do
    ip="10.0.70.${i}"
    # macOS compatible nc
    if nc -zv -G 1 "${ip}" 50000 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}Found Talos at ${ip}${NC}"
        NODES+=("${ip}")
    fi
done

if [ ${#NODES[@]} -eq 0 ]; then
    echo -e "${RED}No Talos nodes found!${NC}"
    echo "Troubleshooting:"
    echo "1. Check VM console in Proxmox: https://10.0.70.10:8006"
    echo "2. Ensure VMs are running: ssh root@10.0.70.10 'qm list | grep talos'"
    echo "3. Check if ISO is properly attached"
    exit 1
fi

echo "Found ${#NODES[@]} Talos nodes"

# Sort nodes by IP
IFS=$'\n' SORTED_NODES=($(printf '%s\n' "${NODES[@]}" | sort -t. -k4 -n))
unset IFS

export TALOSCONFIG="${TALOS_DIR}/talosconfig"

# Apply configurations
echo -e "\n${YELLOW}Applying Talos configurations...${NC}"

# Control planes
for i in 0 1 2; do
    if [ $i -lt ${#SORTED_NODES[@]} ]; then
        node="${SORTED_NODES[$i]}"
        config_num=$((i + 1))
        config_file="${TALOS_DIR}/controlplane-${config_num}.yaml"
        
        if [ -f "$config_file" ]; then
            echo -e "${GREEN}Configuring control plane ${config_num}: ${node} -> ${CP_IPS[$i]}${NC}"
            talosctl apply-config \
                --insecure \
                --nodes "${node}" \
                --endpoints "${node}" \
                --file "${config_file}" || {
                echo -e "${YELLOW}Warning: Failed to apply config to ${node}${NC}"
            }
        else
            echo -e "${RED}Missing config: ${config_file}${NC}"
        fi
        sleep 5
    fi
done

# Workers
for i in 0 1 2; do
    node_index=$((i + 3))
    if [ $node_index -lt ${#SORTED_NODES[@]} ]; then
        node="${SORTED_NODES[$node_index]}"
        config_num=$((i + 1))
        config_file="${TALOS_DIR}/worker-${config_num}.yaml"
        
        if [ -f "$config_file" ]; then
            echo -e "${GREEN}Configuring worker ${config_num}: ${node} -> ${WORKER_IPS[$i]}${NC}"
            talosctl apply-config \
                --insecure \
                --nodes "${node}" \
                --endpoints "${node}" \
                --file "${config_file}" || {
                echo -e "${YELLOW}[WARNING] Failed to apply config to ${node}${NC}"
            }
        else
            echo -e "${RED}Missing config: ${config_file}${NC}"
        fi
        sleep 5
    fi
done

# Step 4: Wait for static IPs
echo -e "\n${YELLOW}[Step 4/6] Waiting for nodes to reboot with static IPs...${NC}"
echo "Waiting 90 seconds for reboot..."
sleep 90

# Verify static IPs
echo -e "\n${YELLOW}Verifying static IP configuration...${NC}"
READY_COUNT=0
for ip in "${CP_IPS[@]}" "${WORKER_IPS[@]}"; do
    if nc -zv -G 1 "${ip}" 50000 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}[OK] ${ip} ready${NC}"
        READY_COUNT=$((READY_COUNT + 1))
    else
        echo -e "${RED}[FAIL] ${ip} not ready${NC}"
    fi
done

if [ $READY_COUNT -lt 3 ]; then
    echo -e "${YELLOW}Only ${READY_COUNT}/6 nodes ready. Waiting another 60 seconds...${NC}"
    sleep 60
    
    # Final check
    READY_COUNT=0
    for ip in "${CP_IPS[@]}"; do
        nc -zv -G 1 "${ip}" 50000 2>&1 | grep -q "succeeded" && READY_COUNT=$((READY_COUNT + 1))
    done
fi

if [ $READY_COUNT -lt 1 ]; then
    echo -e "${RED}No control plane nodes ready. Cannot bootstrap.${NC}"
    echo "Manual intervention required:"
    echo "1. Check node status: for ip in ${CP_IPS[@]}; do nc -zv -G 1 \$ip 50000; done"
    echo "2. Check VM console for errors"
    echo "3. Run this script again when nodes are ready"
    exit 1
fi

# Step 5: Bootstrap cluster
echo -e "\n${YELLOW}[Step 5/6] Bootstrapping Kubernetes cluster...${NC}"

# Try to use first available control plane
BOOTSTRAP_NODE=""
for ip in "${CP_IPS[@]}"; do
    if nc -zv -G 1 "${ip}" 50000 2>&1 | grep -q "succeeded"; then
        BOOTSTRAP_NODE="${ip}"
        break
    fi
done

if [ -z "$BOOTSTRAP_NODE" ]; then
    echo -e "${RED}No control plane nodes available for bootstrap!${NC}"
    exit 1
fi

echo -e "${GREEN}Bootstrapping on ${BOOTSTRAP_NODE}${NC}"

# Configure talosctl
talosctl config endpoint "${BOOTSTRAP_NODE}" 2>/dev/null || true
talosctl config node "${BOOTSTRAP_NODE}"

# Bootstrap
if talosctl bootstrap; then
    echo -e "${GREEN}Bootstrap successful!${NC}"
else
    echo -e "${YELLOW}Bootstrap failed, retrying with explicit parameters...${NC}"
    if ! talosctl bootstrap --nodes "${BOOTSTRAP_NODE}" --endpoints "${BOOTSTRAP_NODE}"; then
        echo -e "${RED}Bootstrap failed!${NC}"
        echo "Try manually:"
        echo "  export TALOSCONFIG=${TALOS_DIR}/talosconfig"
        echo "  talosctl bootstrap --nodes ${BOOTSTRAP_NODE} --endpoints ${BOOTSTRAP_NODE}"
        exit 1
    fi
fi

# Wait for cluster health
echo -e "\n${YELLOW}Waiting for cluster to be healthy...${NC}"
if talosctl health --wait-timeout 5m; then
    echo -e "${GREEN}Cluster is healthy!${NC}"
else
    echo -e "${YELLOW}Health check timed out, but cluster may still be starting.${NC}"
    echo "Check manually: talosctl health"
fi

# Step 6: Configure VIP
echo -e "\n${YELLOW}[Step 6/6] Configuring cluster VIP...${NC}"

# Apply VIP configuration to all control plane nodes
VIP_SUCCESS=0
VIP_TOTAL=0

for i in "${!CP_IPS[@]}"; do
    ip="${CP_IPS[$i]}"
    idx=$((i + 1))
    vip_patch="${TALOS_DIR}/vip-patch-cp-${idx}.yaml"
    
    if [ -f "$vip_patch" ]; then
        VIP_TOTAL=$((VIP_TOTAL + 1))
        echo -e "${GREEN}Applying VIP configuration to ${ip}...${NC}"
        
        if talosctl patch machineconfig --patch @"${vip_patch}" --nodes "${ip}"; then
            echo -e "${GREEN}[OK] VIP patch applied to ${ip}${NC}"
            VIP_SUCCESS=$((VIP_SUCCESS + 1))
        else
            echo -e "${RED}[FAIL] Failed to apply VIP patch to ${ip}${NC}"
        fi
        
        # Small delay between applications
        sleep 10
    else
        echo -e "${RED}Missing VIP patch: ${vip_patch}${NC}"
    fi
done

if [ $VIP_SUCCESS -gt 0 ]; then
    echo -e "\n${YELLOW}Waiting for VIP to stabilize...${NC}"
    sleep 30
    
    # Test VIP connectivity
    echo -e "\n${YELLOW}Testing VIP connectivity...${NC}"
    if nc -zv -G 1 "${CLUSTER_VIP}" 6443 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}[OK] VIP ${CLUSTER_VIP} is accessible${NC}"
        
        # Update talosctl to use VIP
        talosctl config endpoint "${CLUSTER_VIP}"
        echo -e "${GREEN}[OK] talosctl configured to use VIP${NC}"
    else
        echo -e "${YELLOW}[WARNING] VIP not yet accessible, using individual endpoints${NC}"
        # Fallback to first working node
        talosctl config endpoint "${BOOTSTRAP_NODE}"
    fi
else
    echo -e "${RED}Failed to apply VIP to any nodes${NC}"
fi

# Get kubeconfig
echo -e "\n${YELLOW}Getting kubeconfig...${NC}"
if talosctl kubeconfig; then
    echo -e "${GREEN}Kubeconfig saved!${NC}"
else
    echo -e "${YELLOW}Failed to get kubeconfig. Try manually:${NC}"
    echo "  talosctl kubeconfig --nodes ${BOOTSTRAP_NODE} --endpoints ${BOOTSTRAP_NODE}"
fi

# Final status
echo -e "\n${BLUE}=== Deployment Complete ===${NC}"
echo ""
echo "Cluster VIP: ${CLUSTER_VIP}"
echo "Cluster endpoints:"
for ip in "${CP_IPS[@]}"; do
    echo "  - ${ip}"
done
echo ""
if [ $VIP_SUCCESS -gt 0 ]; then
    echo -e "${GREEN}[OK] VIP configuration applied successfully${NC}"
    echo "API Server: https://${CLUSTER_VIP}:6443"
else
    echo -e "${YELLOW}[WARNING] VIP configuration incomplete${NC}"
    echo "API Server: https://${BOOTSTRAP_NODE}:6443"
fi
echo ""
echo "Next steps:"
echo "  1. Check nodes: kubectl get nodes"
echo "  2. Install CNI (if not ready):"
echo "     helm repo add cilium https://helm.cilium.io/"
echo "     helm install cilium cilium/cilium --namespace kube-system \\"
echo "       --set ipam.mode=kubernetes \\"
echo "       --set kubeProxyReplacement=true"
echo "  3. Check pods: kubectl get pods -A"
echo ""
echo -e "${GREEN}Cluster configuration complete!${NC}"
