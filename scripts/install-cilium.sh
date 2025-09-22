#!/bin/bash

set -e

echo "Installing Cilium CNI..."

# Add Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium
helm install cilium cilium/cilium --version 1.18.0 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set bgpControlPlane.enabled=true \
  --set bpf.mount.enabled=false \
  --set loadBalancer.mode=bgp \
  --set loadBalancer.serviceTopology=true \
  --set k8sServiceHost=10.0.70.250 \
  --set k8sServicePort=6443 \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup 

echo "Waiting for Cilium to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s

echo "Cilium installed successfully!"
