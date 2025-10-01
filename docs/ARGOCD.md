# ArgoCD GitOps Setup

## Overview

This homelab uses ArgoCD for GitOps-based deployment and management of all Kubernetes resources. ArgoCD automatically syncs your Git repository with the cluster state.

## Architecture
GitHub Repository (Source of Truth)
↓
ArgoCD (Monitors & Syncs)
↓
Kubernetes Cluster (Desired State)

### App of Apps Pattern

We use ApplicationSet with the "App of Apps" pattern:
ApplicationSet: cluster-components
├── Wave 1: sealed-secrets
├── Wave 2: cert-manager
├── Wave 3: cert-manager-config
├── Wave 4: gateway
├── Wave 5: cilium-config
├── Wave 6: routes
├── Wave 7: bootstrap
└── Wave 8: cluster-info

## Access ArgoCD

### Get Credentials
Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

Get server URL
kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

## Managing Applications
### View All Applications
Using kubectl
kubectl get applications -n argocd
kubectl get applications -n argocd -o wide

Using ArgoCD CLI
argocd app list
argocd app list -o wide

### View Application Details
Using kubectl
kubectl describe application sealed-secrets -n argocd
kubectl get application sealed-secrets -n argocd -o yaml

Using ArgoCD CLI
argocd app get sealed-secrets
argocd app get sealed-secrets --show-operation
### Sync Applications
Sync specific application (kubectl)
kubectl patch application sealed-secrets -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

Sync specific application (ArgoCD CLI)
argocd app sync sealed-secrets

Sync all applications
kubectl get applications -n argocd -o name | \
  xargs -I {} kubectl patch {} -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

Or with ArgoCD CLI
argocd app sync -l app.kubernetes.io/part-of=cluster-components
### View Sync Status
Watch sync status
kubectl get applications -n argocd -w

Get sync status for all apps
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'
# GitOps Workflow
## 1. Make Changes in Git
Create or modify a resource
vi clusters/production/network/routes/my-new-route.yaml

Add the file
git add clusters/production/network/routes/my-new-route.yaml

Commit
git commit -m "Add new HTTPRoute for my-service"

Push
git push
## 2. ArgoCD Automatically Syncs
ArgoCD polls the repository every 3 minutes. It will:

Detect the change
Compare with cluster state
Automatically sync (if auto-sync enabled)
Apply the changes

## 3. Verify Changes
Check application sync status
kubectl get application routes -n argocd

Verify the resource was created
kubectl get httproute my-new-route
## Force Immediate Sync
If you don't want to wait for the 3-minute poll:
kubectl patch application routes -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
