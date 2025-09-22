#!/bin/bash

set -e

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD installed!"
echo "Admin password: ${ARGOCD_PASSWORD}"
echo "Port forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
