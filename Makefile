.PHONY: help deploy bootstrap destroy plan status clean

# Default target
help:
	@echo "Homelab Kubernetes Cluster Management"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy      - Full deployment (Stage 1 + Stage 2)"
	@echo "  make plan        - Show what Terraform will do"
	@echo "  make bootstrap   - Run Stage 2 only (ArgoCD + Apps)"
	@echo "  make status      - Show cluster status"
	@echo "  make destroy     - Destroy the cluster"
	@echo "  make clean       - Clean up output files"
	@echo ""

# Full deployment (both stages)
deploy: plan
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Stage 1: Deploying Infrastructure with OpenTofu"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@cd infrastructure/opentofu && tofu apply -auto-approve
	@echo ""
	@echo "Stage 1 complete. Waiting 30 seconds for cluster stabilization..."
	@sleep 30
	@echo ""
	@$(MAKE) bootstrap

# Show Terraform plan
plan:
	@echo "Planning infrastructure changes..."
	@cd infrastructure/opentofu && tofu plan

# Stage 2 only (useful for re-running bootstrap)
bootstrap:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Stage 2: Bootstrapping GitOps Platform"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@./bootstrap.sh

# Show cluster status
status:
	@echo "Cluster Status:"
	@echo ""
	@echo "Nodes:"
	@kubectl get nodes -o wide || echo "  Cluster not accessible"
	@echo ""
	@echo "ArgoCD Applications:"
	@kubectl get applications -n argocd 2>/dev/null || echo "  ArgoCD not installed yet"
	@echo ""
	@echo "Gateway Status:"
	@kubectl get gateway -A 2>/dev/null || echo "  No gateways deployed"

# Destroy cluster
destroy:
	@echo "WARNING: This will destroy the entire cluster!"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	@cd infrastructure/opentofu && tofu destroy -auto-approve
	@echo "Cluster destroyed"

# Clean up generated files
clean:
	@echo "Cleaning up generated files..."
	@rm -rf infrastructure/opentofu/output/
	@rm -f infrastructure/opentofu/*.tfplan
	@echo "Cleaned"

# Initialize Terraform
init:
	@echo "Initializing OpenTofu..."
	@cd infrastructure/opentofu && tofu init
	@echo "Initialized"
