# Secrets Management with Sealed Secrets
## Creating Sealed Secrets

### Basic Secret
    kubectl create secret generic my-secret \
      --from-literal=username=admin \
      --from-literal=password=secret123 \
      --namespace=default \
      --dry-run=client -o yaml | \
      kubeseal -o yaml > my-sealed-secret.yaml
### From File
    kubectl create secret generic my-secret \
      --from-file=./secret.txt \
      --namespace=default \
      --dry-run=client -o yaml | \
      kubeseal -o yaml > my-sealed-secret.yaml
### TLS Secret
    kubectl create secret tls my-tls-secret \
      --cert=path/to/cert.crt \
      --key=path/to/key.key \
      --namespace=default \
      --dry-run=client -o yaml | \
      kubeseal -o yaml > my-tls-sealed-secret.yaml
## Deploying Sealed Secrets
    # Commit the sealed secret
    git add my-sealed-secret.yaml
    git commit -m "Add sealed secret"
    git push
    
    # ArgoCD will automatically sync
    # Or apply directly:
    kubectl apply -f my-sealed-secret.yaml
## Verifying Secrets
    # Check sealed secret
    kubectl get sealedsecret my-secret
    
    # Check if regular secret was created
    kubectl get secret my-secret
    
    # View secret data (decoded)
    kubectl get secret my-secret -o jsonpath='{.data.username}' | base64 -d
## Backup Sealed Secrets Keys

** CRITICAL: Backup these keys immediately!**
    kubectl get secret -n sealed-secrets \
      -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
      -o yaml > sealed-secrets-key-backup.yaml
    
    # Store securely:
    # - Password manager
    # - Encrypted cloud storage
    # - Hardware security module
    # DO NOT commit to Git!
## Restoring Keys
    # Restore the key
    kubectl apply -f sealed-secrets-key-backup.yaml
    
    # Restart controller
    kubectl rollout restart deployment/sealed-secrets-controller -n sealed-secrets
## Rotating Keys

Keys are automatically rotated every 30 days.
    # Check key age
    kubectl get secrets -n sealed-secrets \
      -l sealedsecrets.bitnami.com/sealed-secrets-key
    
    # Force rotation (if needed)
    kubectl delete secrets -n sealed-secrets \
      -l sealedsecrets.bitnami.com/sealed-secrets-key=active
    kubectl rollout restart deployment/sealed-secrets-controller -n sealed-secrets
