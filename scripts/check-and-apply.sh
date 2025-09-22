#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="${SCRIPT_DIR}/../infrastructure/talos"

# Configuration
CP_IPS=("10.0.70.70" "10.0.70.71" "10.0.70.72")
WORKER_IPS=("10.0.70.80" "10.0.70.81" "10.0.70.82")

export TALOSCONFIG="${TALOS_DIR}/talosconfig"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Talos Deployment Check and Apply ===${NC}"

# Step 1: Check and start VMs
echo -e "\n${YELLOW}Step 1: Checking VM status in Proxmox...${NC}"
for vmid in 200 201 202 300 301 302; do
    status=$(ssh root@10.0.10.10 "qm status $vmid 2>/dev/null | grep status" | awk '{print $2}' || echo "not found")
    echo "VM $vmid: $status"
    if [ "$status" = "stopped" ] || [ "$status" = "not found" ]; then
        echo "  Starting VM $vmid..."
        ssh root@10.0.10.10 "qm start $vmid" 2>/dev/null || true
    fi
done

# Step 2: Wait for VMs to boot
echo -e "\n${YELLOW}Step 2: Waiting 90 seconds for VMs to boot...${NC}"
sleep 90

# Step 3: Scan network for Talos nodes (macOS compatible)
echo -e "\n${YELLOW}Step 3: Scanning network for Talos nodes...${NC}"
FOUND_IPS=()

# Use nc with macOS-compatible options
for i in {1..254}; do
    ip="10.0.10.${i}"
    # macOS nc uses -G for timeout instead of -w
    if nc -zv -G 1 "${ip}" 50000 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}✓ Found Talos API at ${ip}${NC}"
        FOUND_IPS+=("${ip}")
    fi
done

echo -e "\n${BLUE}Found ${#FOUND_IPS[@]} Talos nodes total${NC}"

if [ ${#FOUND_IPS[@]} -eq 0 ]; then
    echo -e "\n${RED}No Talos nodes found!${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check VM console in Proxmox: https://10.0.10.10:8006"
    echo "2. Verify ISO is attached to VMs"
    echo "3. Try manual fix:"
    echo "   for vm in 200 201 202 300 301 302; do"
    echo "     ssh root@10.0.70.10 \"qm set \$vm --ide2 local:iso/nocloud-amd64.iso,media=cdrom\""
    echo "     ssh root@10.0.70.10 \"qm stop \$vm && qm start \$vm\""
    echo "   done"
    exit 1
fi

# Step 4: Sort nodes by IP
IFS=$'\n' SORTED_IPS=($(printf '%s\n' "${FOUND_IPS[@]}" | sort -t. -k4 -n))
unset IFS

echo -e "\n${YELLOW}Step 4: Nodes found (sorted by IP):${NC}"
for ip in "${SORTED_IPS[@]}"; do
    echo "  - ${ip}"
done

# Step 5: Apply configurations
echo -e "\n${YELLOW}Step 5: Applying Talos configurations...${NC}"

# Apply control plane configs to first 3 nodes
for i in 0 1 2; do
    if [ $i -lt ${#SORTED_IPS[@]} ]; then
        node="${SORTED_IPS[$i]}"
        config_num=$((i + 1))
        config_file="${TALOS_DIR}/controlplane-${config_num}.yaml"
        target_ip="${CP_IPS[$i]}"
        
        if [ ! -f "$config_file" ]; then
            echo -e "${RED}Config file missing: $config_file${NC}"
            continue
        fi
        
        echo -e "${GREEN}Applying control plane ${config_num} to ${node} -> ${target_ip}${NC}"
        if talosctl apply-config \
            --insecure \
            --nodes "${node}" \
            --endpoints "${node}" \
            --file "${config_file}"; then
            echo "  ✓ Success"
        else
            echo -e "${RED}  ✗ Failed${NC}"
        fi
        sleep 5
    fi
done

# Apply worker configs to next 3 nodes
for i in 0 1 2; do
    node_index=$((i + 3))
    if [ $node_index -lt ${#SORTED_IPS[@]} ]; then
        node="${SORTED_IPS[$node_index]}"
        config_num=$((i + 1))
        config_file="${TALOS_DIR}/worker-${config_num}.yaml"
        target_ip="${WORKER_IPS[$i]}"
        
        if [ ! -f "$config_file" ]; then
            echo -e "${RED}Config file missing: $config_file${NC}"
            continue
        fi
        
        echo -e "${GREEN}Applying worker ${config_num} to ${node} -> ${target_ip}${NC}"
        if talosctl apply-config \
            --insecure \
            --nodes "${node}" \
            --endpoints "${node}" \
            --file "${config_file}"; then
            echo "  ✓ Success"
        else
            echo -e "${RED}  ✗ Failed${NC}"
        fi
        sleep 5
    fi
done

# Step 6: Wait for reboot with static IPs
echo -e "\n${YELLOW}Step 6: Waiting 90 seconds for nodes to reboot with static IPs...${NC}"
sleep 90

# Step 7: Verify static IPs
echo -e "\n${YELLOW}Step 7: Verifying static IP configuration...${NC}"
SUCCESS_COUNT=0

for ip in "${CP_IPS[@]}" "${WORKER_IPS[@]}"; do
    if nc -zv -G 1 "${ip}" 50000 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}✓ ${ip} - READY${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗ ${ip} - NOT RESPONDING${NC}"
    fi
done

echo -e "\n${BLUE}=== RESULTS ===${NC}"
echo "Nodes ready: ${SUCCESS_COUNT}/6"

if [ $SUCCESS_COUNT -eq 6 ]; then
    echo -e "${GREEN}SUCCESS! All nodes configured.${NC}"
    echo ""
    echo "Bootstrap the cluster:"
    echo "  export TALOSCONFIG=${TALOS_DIR}/talosconfig"
    echo "  talosctl config endpoint 10.0.70.70"
    echo "  talosctl config node 10.0.70.70"
    echo "  talosctl bootstrap"
    echo "  talosctl health"
    echo "  talosctl kubeconfig"
    echo "  kubectl get nodes"
elif [ $SUCCESS_COUNT -ge 3 ]; then
    echo -e "${YELLOW}PARTIAL SUCCESS: ${SUCCESS_COUNT} nodes configured.${NC}"
    echo "You may be able to bootstrap with available control planes."
else
    echo -e "${RED}Configuration failed. Nodes may still be rebooting.${NC}"
    echo "Wait 60 seconds and run this script again."
fi
