# Kubernetes Troubleshooting Command Reference

## Basic Cluster Health

```bash
kubectl get nodes                                    # Show cluster nodes and their status
kubectl get nodes -o wide                            # Show nodes with more details (IPs, OS, etc)
kubectl get pods -A                                  # List all pods in all namespaces
kubectl get all -n <namespace>                       # Show all resources in a namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20  # Recent events
kubectl describe <resource> <name> -n <namespace>    # Detailed info about a resource
kubectl logs <pod-name> -n <namespace> --tail=50     # View pod logs
kubectl logs -n <namespace> deployment/<name> --tail=50  # View deployment logs
```

## ArgoCD Application Management

```bash
kubectl get applications -n argocd                   # List all ArgoCD applications
kubectl get applications -n argocd -o wide           # Applications with additional columns
kubectl get application <name> -n argocd -o yaml     # Full YAML of an application
kubectl describe application <name> -n argocd        # Detailed application status and events

# Check application sync status
kubectl get application <name> -n argocd -o jsonpath='{.status.sync.status}'

# Check application health
kubectl get application <name> -n argocd -o jsonpath='{.status.health.status}'

# Check what resources are out of sync
kubectl get application <name> -n argocd -o jsonpath='{.status.resources}' | jq

# Check for sync errors
kubectl get application <name> -n argocd -o jsonpath='{.status.conditions}' | jq

# Check operation state (why sync failed)
kubectl get application <name> -n argocd -o jsonpath='{.status.operationState}' | jq

# Force sync an application
kubectl patch application <name> -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Hard refresh (clear cache and recompare)
kubectl patch application <name> -n argocd --type json \
  -p='[{"op": "replace", "path": "/metadata/annotations/argocd.argoproj.io~1refresh", "value": "hard"}]'

# Delete and recreate application (forces ApplicationSet to regenerate)
kubectl delete application <name> -n argocd

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Get ArgoCD server URL
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Cilium Networking

```bash
kubectl get pods -n kube-system -l k8s-app=cilium    # Cilium agent pods
kubectl get pods -n kube-system -l name=cilium-operator  # Cilium operator

# Check Cilium LoadBalancer IP pool
kubectl get ciliumloadbalancerippool
kubectl describe ciliumloadbalancerippool first-pool

# Check L2 announcement policy
kubectl get ciliuml2announcementpolicy -n kube-system
kubectl describe ciliuml2announcementpolicy default-l2-announcement-policy -n kube-system

# Check Cilium configuration
kubectl get configmap cilium-config -n kube-system -o yaml | grep <setting>
kubectl get configmap cilium-values -n kube-system -o yaml

# Restart Cilium components
kubectl rollout restart daemonset/cilium -n kube-system
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system

# Check Cilium logs
kubectl logs -n kube-system daemonset/cilium --tail=50
kubectl logs -n kube-system deployment/cilium-operator --tail=100 | grep -i gateway
```

## Gateway API

```bash
kubectl get crd | grep gateway                       # Check if Gateway API CRDs exist
kubectl get gatewayclass                             # List gateway classes
kubectl get gateways -A                              # List all gateways
kubectl get gateways -n gateway -o wide              # Gateways with IPs
kubectl describe gateway <name> -n gateway           # Detailed gateway status
kubectl get httproutes -A                            # List HTTP routes
kubectl describe httproute <name> -n <namespace>     # Route details and status

# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

## Sealed Secrets

```bash
kubectl get pods -n sealed-secrets                   # Sealed secrets controller
kubectl get crd | grep sealed                        # Check if SealedSecret CRD exists
kubectl get sealedsecret -A                          # List sealed secrets
kubectl get sealedsecret <name> -n <namespace>       # Check sealed secret status
kubectl get secret <name> -n <namespace>             # Check if secret was unsealed
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller --tail=50  # Controller logs

# Fetch public certificate for sealing
kubeseal --fetch-cert --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets

# Create a sealed secret
kubectl create secret generic <name> \
  --from-literal=key=value \
  --namespace=<namespace> \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets \
    -o yaml > sealed-secret.yaml

# Install SealedSecret CRD manually
kubectl apply -f https://raw.githubusercontent.com/bitnami-labs/sealed-secrets/v0.27.1/helm/sealed-secrets/crds/bitnami.com_sealedsecrets.yaml

# Backup sealed-secrets encryption key
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml
```

## cert-manager

```bash
kubectl get pods -n cert-manager                     # cert-manager components
kubectl get clusterissuer                            # List cluster issuers
kubectl get clusterissuer <name>                     # Check issuer status
kubectl describe clusterissuer <name>                # Detailed issuer info
kubectl get certificate -A                           # List certificates
kubectl describe certificate <name> -n <namespace>   # Certificate status

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=50
kubectl logs -n cert-manager deployment/cert-manager-webhook --tail=50
kubectl logs -n cert-manager deployment/cert-manager-cainjector --tail=100

# Check webhook configuration
kubectl get validatingwebhookconfiguration cert-manager-webhook -o yaml
kubectl get validatingwebhookconfiguration cert-manager-webhook -o yaml | grep caBundle

# Check if webhook service exists
kubectl get svc cert-manager-webhook -n cert-manager

# Restart cert-manager components
kubectl rollout restart deployment/cert-manager -n cert-manager
kubectl rollout restart deployment/cert-manager-webhook -n cert-manager
kubectl rollout restart deployment/cert-manager-cainjector -n cert-manager

# Scale webhook deployment
kubectl scale deployment cert-manager-webhook -n cert-manager --replicas=0
kubectl scale deployment cert-manager-webhook -n cert-manager --replicas=1

# Delete webhook configuration (forces recreation)
kubectl delete validatingwebhookconfiguration cert-manager-webhook

# Patch webhook to make failures non-blocking
kubectl patch validatingwebhookconfiguration cert-manager-webhook \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value": "Ignore"}]'

# Create resource without webhook validation
kubectl apply -f <file> --validate=false
```

## Kustomize Testing

```bash
kubectl kustomize <path>                             # Preview what kustomize will generate
kubectl apply -k <path>                              # Apply kustomization
kubectl apply -k <path> --dry-run=client             # Test without applying
kubectl delete -k <path>                             # Delete resources from kustomization
```

## Service and LoadBalancer

```bash
kubectl get svc -A                                   # List all services
kubectl get svc -A | grep LoadBalancer               # Only LoadBalancer services
kubectl get svc <name> -n <namespace> -o yaml        # Service details
kubectl describe svc <name> -n <namespace>           # Service details with events
kubectl patch svc <name> -n <namespace> -p '{"spec": {"type": "LoadBalancer"}}'  # Change service type
```

## Deployment Management

```bash
kubectl get deployment <name> -n <namespace>         # Deployment status
kubectl describe deployment <name> -n <namespace>    # Detailed deployment info
kubectl rollout restart deployment/<name> -n <namespace>  # Restart deployment
kubectl rollout status deployment/<name> -n <namespace>   # Wait for rollout to complete
kubectl scale deployment <name> -n <namespace> --replicas=<n>  # Scale deployment
```

## RBAC Troubleshooting

```bash
kubectl get clusterrole <name>                       # View cluster role
kubectl get clusterrolebinding <name>                # View cluster role binding
kubectl describe clusterrole <name>                  # Role permissions
kubectl describe clusterrolebinding <name>           # Role binding details

# Create cluster role
kubectl create clusterrole <name> --verb=get,list,watch --resource=<resource>

# Create cluster role binding
kubectl create clusterrolebinding <name> \
  --clusterrole=<role> \
  --serviceaccount=<namespace>:<sa-name>
```

## Testing Routes

```bash
# Get gateway IP
EXTERNAL_IP=$(kubectl get gateway external -n gateway -o jsonpath='{.status.addresses[0].value}')

# Test HTTP route
curl -H "Host: test.mill3r.la" http://$EXTERNAL_IP

# Verbose curl for troubleshooting
curl -v -H "Host: test.mill3r.la" http://$EXTERNAL_IP
```

## General Troubleshooting Patterns

```bash
# Watch resources update in real-time
kubectl get <resource> -n <namespace> -w

# Check resource in specific output format
kubectl get <resource> <name> -n <namespace> -o yaml
kubectl get <resource> <name> -n <namespace> -o json
kubectl get <resource> <name> -n <namespace> -o jsonpath='{.status}'

# Delete stuck resources
kubectl delete <resource> <name> -n <namespace>
kubectl delete <resource> <name> -n <namespace> --force --grace-period=0

# Check all CRDs
kubectl get crd

# Check API resources available
kubectl api-resources | grep <search-term>
```

