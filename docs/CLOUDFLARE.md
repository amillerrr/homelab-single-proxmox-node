# Cloudflare API Token Setup

This guide walks you through creating a Cloudflare API token for cert-manager to perform DNS-01 ACME challenges for Let's Encrypt certificates.

## Prerequisites

- Cloudflare account
- Domain managed by Cloudflare (`mill3r.la`)
- Access to create API tokens

## Step 1: Login to Cloudflare

1. Go to https://dash.cloudflare.com/
2. Log in with your account credentials

## Step 2: Navigate to API Tokens

1. Click on your **profile icon** (top right corner)
2. Select **My Profile**
3. Click **API Tokens** in the left sidebar
4. Click **Create Token** button

## Step 3: Create Token

### Option A: Use Template (Recommended)

1. Find **"Edit zone DNS"** template
2. Click **Use template**
3. Continue to configuration

### Option B: Create Custom Token

1. Click **Create Custom Token**
2. Give it a descriptive name: `cert-manager-dns01`

## Step 4: Configure Token Permissions

### Permissions

Add the following permissions:

1. **Zone - DNS - Edit**
   - Click **+ Add more**
   - Select **Zone** from first dropdown
   - Select **DNS** from second dropdown
   - Select **Edit** from third dropdown

2. **Zone - Zone - Read**
   - Click **+ Add more** again
   - Select **Zone** from first dropdown
   - Select **Zone** from second dropdown
   - Select **Read** from third dropdown

### Zone Resources

1. Select **Include** from the dropdown
2. Choose **Specific zone**
3. Select **mill3r.la** from the zone dropdown

### Client IP Address Filtering (Optional)

- **For static IP:** Use the public IP
- **For dynamic IP:** Leave as "All IPs"

### TTL

- **Start date:** Now
- **End date:** Never (or set expiration for key rotation)

## Step 5: Review Token Configuration

Your token summary should look like this:
Token Name: cert-manager-dns01
Permissions:

Zone:DNS:Edit
Zone:Zone:Read

Zone Resources:

Include: mill3r.la (Specific zone)

Client IP Address Filtering:

All IPs (or your specific IP)

TTL:

Start: Now
End: Never

## Step 6: Create Token

1. Click **Continue to summary**
2. Review the configuration
3. Click **Create Token**

## Step 7: Save Your Token

**CRITICAL: You will only see this token once!**

## Step 8: Create Sealed Secret
Now create the sealed secret for your cluster:
Create sealed secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token="YOUR_CLOUDFLARE_TOKEN_HERE" \
  --namespace=cert-manager \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > clusters/production/overlays/production/cert-manager/cloudflare-token-sealed.yaml

Verify sealed secret was created
cat clusters/production/overlays/production/cert-manager/cloudflare-token-sealed.yaml

## Step 9: Deploy via GitOps
Add sealed secret to Git
git add clusters/production/overlays/production/cert-manager/cloudflare-token-sealed.yaml

Commit
git commit -m "Add Cloudflare API token sealed secret"

Push
git push

ArgoCD will automatically sync within 3 minutes
Or force immediate sync:
kubectl patch application cert-manager-config -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
## Step 10: Verify Deployment
Check if sealed secret exists
kubectl get sealedsecret cloudflare-api-token -n cert-manager

Check if regular secret was created
kubectl get secret cloudflare-api-token -n cert-manager

Verify secret data (should see encrypted value)
kubectl get secret cloudflare-api-token -n cert-manager -o yaml

Test certificate issuance
kubectl get certificate -n gateway
kubectl describe certificate cert-homelab -n gateway

## Troubleshooting
### Token Verification Failed
Verify token permissions
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
### Certificate Not Issuing
Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

Check certificate status
kubectl describe certificate cert-homelab -n gateway

Check certificate request
kubectl get certificaterequest -n gateway
kubectl describe certificaterequest <name> -n gateway

## Token Rotation
### When to Rotate

Every 90 days (recommended)
If token is compromised
When team members change
Regular security audits

### How to Rotate

1. Create new token (follow steps above)
2. Create new sealed secret with new token
3. Commit and push to Git
4. ArgoCD syncs automatically
5. Verify certificates still renewing
6. Delete old token in Cloudflare

Create new sealed secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token="NEW_TOKEN_HERE" \
  --namespace=cert-manager \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > clusters/production/overlays/production/cert-manager/cloudflare-token-sealed.yaml

Commit and push
git add clusters/production/overlays/production/cert-manager/cloudflare-token-sealed.yaml
git commit -m "Rotate Cloudflare API token"
git push
