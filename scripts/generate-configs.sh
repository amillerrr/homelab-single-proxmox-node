#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="${SCRIPT_DIR}/../infrastructure/talos"
SECRETS_DIR="${TALOS_DIR}/secrets"

# Configuration
CLUSTER_NAME="talos-k8s"
CLUSTER_VIP="10.0.70.250"
GATEWAY="10.0.70.1"
CP_IPS=("10.0.70.70" "10.0.70.71" "10.0.70.72")
WORKER_IPS=("10.0.70.80" "10.0.70.81" "10.0.70.82")

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Generating Talos configurations...${NC}"

mkdir -p "${SECRETS_DIR}"

# Generate secrets once
if [ ! -f "${SECRETS_DIR}/secrets.yaml" ]; then
    echo -e "${YELLOW}Generating new secrets...${NC}"
    talosctl gen secrets -o "${SECRETS_DIR}/secrets.yaml"
fi

# Generate control plane configs
for i in "${!CP_IPS[@]}"; do
    ip="${CP_IPS[$i]}"
    idx=$((i + 1))
    hostname="talos-cp-$(printf "%02d" ${idx})"
    
    echo "Generating control plane ${idx} config for ${ip}..."
    
    # Create patch file
    cat > "${TALOS_DIR}/patch-cp-${idx}.yaml" <<EOF
machine:
  network:
    hostname: ${hostname}
    interfaces:
      - interface: eth0
        addresses:
          - ${ip}/24
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
  install:
    disk: /dev/sda
    image: factory.talos.dev/nocloud-installer/95d432d6bb450a67e801a6ae77c96a67e38820b62ba4159ae7e997e1695207f7:v1.11.1
    wipe: false
  kubelet:
    clusterDNS:
      - 10.96.0.10
    extraConfig:
      serverTLSBootstrap: false
      maxPods: 250
  sysctls:
    net.core.bpf_jit_enable: "1"
    net.ipv4.conf.all.rp_filter: "0"
    net.ipv4.conf.default.rp_filter: "0"
    net.ipv4.ip_forward: "1"
    net.ipv6.conf.all.forwarding: "1"
    net.ipv4.conf.all.accept_local: "1"
    net.ipv4.conf.all.arp_announce: "2"
    net.ipv4.conf.all.arp_ignore: "1"
    net.ipv4.fib_multipath_use_neigh: "1"
  kernel:
    modules:
      - name: br_netfilter
      - name: overlay
      - name: ip_tables
      - name: iptable_nat
      - name: iptable_filter
      - name: iptable_mangle
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        - os:reader
      allowedKubernetesNamespaces:
        - kube-system
        - cilium
cluster:
  allowSchedulingOnControlPlanes: true
  controllerManager:
    extraArgs:
      bind-address: 0.0.0.0
  etcd:
    advertisedSubnets:
      - 10.0.70.0/24
  apiServer:
    certSANs:
      - ${ip}
      - ${CLUSTER_VIP}
      - localhost
      - 127.0.0.1
  controlPlane:
    endpoint: https://${CLUSTER_VIP}:6443
    localAPIServerPort: 443
  clusterName: ${CLUSTER_NAME}
  network:
    cni:
      name: none
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
  proxy:
    disabled: true
  scheduler:
    extraArgs:
      bind-address: 0.0.0.0
EOF
    
    # Generate VIP patch for this control plane node
    cat > "${TALOS_DIR}/vip-patch-cp-${idx}.yaml" <<EOF
machine:
  network:
    interfaces:
      - interface: eth0
        addresses:
          - ${ip}/24
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
        vip:
          ip: ${CLUSTER_VIP}
EOF
    
    # Generate config with patch
    talosctl gen config "${CLUSTER_NAME}" "https://${CLUSTER_VIP}:6443" \
        --with-secrets "${SECRETS_DIR}/secrets.yaml" \
        --config-patch @"${TALOS_DIR}/patch-cp-${idx}.yaml" \
        --output-types controlplane \
        --output "${TALOS_DIR}/controlplane-${idx}.yaml" \
        --force
done

# Generate worker configs
for i in "${!WORKER_IPS[@]}"; do
    ip="${WORKER_IPS[$i]}"
    idx=$((i + 1))
    hostname="talos-worker-$(printf "%02d" ${idx})"
    
    echo "Generating worker ${idx} config for ${ip}..."
    
    # Create patch file
    cat > "${TALOS_DIR}/patch-worker-${idx}.yaml" <<EOF
machine:
  network:
    hostname: ${hostname}
    interfaces:
      - interface: eth0
        addresses:
          - ${ip}/24
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
  install:
    disk: /dev/sda
    image: factory.talos.dev/nocloud-installer/95d432d6bb450a67e801a6ae77c96a67e38820b62ba4159ae7e997e1695207f7:v1.11.1
    wipe: false
  kubelet:
    clusterDNS:
      - 10.96.0.10
    extraConfig:
      serverTLSBootstrap: false
      maxPods: 250
  sysctls:
    net.core.bpf_jit_enable: "1"
    net.ipv4.conf.all.rp_filter: "0"
    net.ipv4.conf.default.rp_filter: "0"
    net.ipv4.ip_forward: "1"
    net.ipv6.conf.all.forwarding: "1"
    net.ipv4.conf.all.accept_local: "1"
    net.ipv4.conf.all.arp_announce: "2"
    net.ipv4.conf.all.arp_ignore: "1"
    net.ipv4.fib_multipath_use_neigh: "1"
  kernel:
    modules:
      - name: br_netfilter
      - name: overlay
      - name: ip_tables
      - name: iptable_nat
      - name: iptable_filter
      - name: iptable_mangle
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        - os:reader
      allowedKubernetesNamespaces:
        - kube-system
        - cilium
cluster:
  clusterName: ${CLUSTER_NAME}
  controlPlane:
    endpoint: https://${CLUSTER_VIP}:6443
EOF
    
    # Generate config with patch
    talosctl gen config "${CLUSTER_NAME}" "https://${CLUSTER_VIP}:6443" \
        --with-secrets "${SECRETS_DIR}/secrets.yaml" \
        --config-patch @"${TALOS_DIR}/patch-worker-${idx}.yaml" \
        --output-types worker \
        --output "${TALOS_DIR}/worker-${idx}.yaml" \
        --force
done

# Generate talosconfig
echo "Generating talosconfig..."
talosctl gen config "${CLUSTER_NAME}" "https://${CLUSTER_VIP}:6443" \
    --with-secrets "${SECRETS_DIR}/secrets.yaml" \
    --output-types talosconfig \
    --output "${TALOS_DIR}/talosconfig" \
    --force

# Clean up temporary patch files (keep VIP patches)
rm -f "${TALOS_DIR}"/patch-cp-*.yaml
rm -f "${TALOS_DIR}"/patch-worker-*.yaml

echo -e "${GREEN}Configuration generation complete!${NC}"
echo -e "${YELLOW}VIP patches generated for post-bootstrap application.${NC}"
ls -la "${TALOS_DIR}/"*.yaml 2>/dev/null | grep -v patch || true
