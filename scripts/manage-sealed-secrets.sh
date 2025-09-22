#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
install_kubeseal() {
    echo -e "${GREEN}Installing kubeseal CLI...${NC}"
    KUBESEAL_VERSION="0.24.5"
    if [ "$(uname)" = "Darwin" ]; then
        OS="darwin"
    else
        OS="linux"
    fi
    
    if [ "$(uname -m)" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$(uname -m)" = "aarch64" ]; then
        ARCH="arm64"
    else
        ARCH="amd64"
    fi
    
    wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-${OS}-${ARCH}.tar.gz
    tar -xvzf kubeseal-${KUBESEAL_VERSION}-${OS}-${ARCH}.tar.gz kubeseal
    sudo install -m 755 kubeseal /usr/local/bin/kubeseal
    rm kubeseal kubeseal-${KUBESEAL_VERSION}-${OS}-${ARCH}.tar.gz
    echo "kubeseal installed successfully"
}

install_sealed_secrets_controller() {
    echo -e "${GREEN}Installing Sealed Secrets controller...${NC}"
    kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/controller.yaml
    
    echo "Waiting for controller to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/sealed-secrets-controller -n kube-system
    echo "Sealed Secrets controller installed"
}

create_sealed_secret() {
    local name=$1
    local namespace=$2
    local key=$3
    local value=$4
    
    if [ -z "$name" ] || [ -z "$namespace" ] || [ -z "$key" ] || [ -z "$value" ]; then
        echo -e "${RED}Usage: create_sealed_secret <name> <namespace> <key> <value>${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Creating sealed secret: ${name} in namespace: ${namespace}${NC}"
    
    # Create the secret and seal it
    echo -n "${value}" | kubectl create secret generic ${name} \
        --namespace=${namespace} \
        --from-file=${key}=/dev/stdin \
        --dry-run=client -o yaml | \
        kubeseal --format=yaml > "${PROJECT_ROOT}/clusters/production/apps/${namespace}/${name}-sealed.yaml"
    
    echo "Sealed secret saved to: clusters/production/apps/${namespace}/${name}-sealed.yaml"
    echo -e "${YELLOW}Remember to commit this file to Git!${NC}"
}

seal_existing_secret() {
    local secret_name=$1
    local namespace=$2
    local output_path=$3
    
    if [ -z "$secret_name" ] || [ -z "$namespace" ]; then
        echo -e "${RED}Usage: seal_existing_secret <secret_name> <namespace> [output_path]${NC}"
        return 1
    fi
    
    if [ -z "$output_path" ]; then
        output_path="${PROJECT_ROOT}/clusters/production/apps/${namespace}/${secret_name}-sealed.yaml"
    fi
    
    echo -e "${GREEN}Sealing existing secret: ${secret_name} from namespace: ${namespace}${NC}"
    
    kubectl get secret ${secret_name} -n ${namespace} -o yaml | \
        kubeseal --format=yaml > "${output_path}"
    
    echo "Sealed secret saved to: ${output_path}"
}

backup_sealed_secrets_key() {
    echo -e "${GREEN}Backing up Sealed Secrets encryption key...${NC}"
    
    local backup_dir="${PROJECT_ROOT}/infrastructure/talos/secrets/sealed-secrets-backup"
    mkdir -p "${backup_dir}"
    
    kubectl get secret -n kube-system sealed-secrets-key -o yaml > "${backup_dir}/sealed-secrets-key-$(date +%Y%m%d-%H%M%S).yaml"
    
    echo -e "${YELLOW}IMPORTANT: Backup saved to ${backup_dir}${NC}"
    echo -e "${YELLOW}Store this backup securely - it's needed for disaster recovery!${NC}"
    echo -e "${RED}Do NOT commit this to Git!${NC}"
}

rotate_sealed_secrets_key() {
    echo -e "${YELLOW}This will rotate the Sealed Secrets encryption key.${NC}"
    echo -e "${YELLOW}Existing sealed secrets will continue to work.${NC}"
    echo -e "Continue? (yes/no)"
    read -r response
    
    if [[ "$response" != "yes" ]]; then
        echo "Key rotation cancelled."
        return
    fi
    
    echo -e "${GREEN}Rotating Sealed Secrets key...${NC}"
    kubectl delete pod -n kube-system -l name=sealed-secrets-controller
    echo "Controller restarted. A new key will be generated automatically."
    
    sleep 10
    backup_sealed_secrets_key
}

show_usage() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}     Sealed Secrets Management Tool            ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    echo "Usage: $0 [command] [arguments]"
    echo ""
    echo "Commands:"
    echo "  install                     - Install Sealed Secrets controller and CLI"
    echo "  create <name> <ns> <key> <value> - Create a new sealed secret"
    echo "  seal <name> <namespace>     - Seal an existing secret"
    echo "  backup                      - Backup encryption keys"
    echo "  rotate                      - Rotate encryption keys"
    echo "  help                        - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 create db-password demo-app password 'mySecretPass123'"
    echo "  $0 seal existing-secret default"
    echo "  $0 backup"
}

# Main script logic
case "${1:-}" in
    install)
        echo -e "${BLUE}Installing Sealed Secrets...${NC}"
        
        # Check if kubeseal is installed
        if ! command -v kubeseal &> /dev/null; then
            install_kubeseal
        else
            echo "kubeseal already installed: $(kubeseal --version 2>&1 | head -n1)"
        fi
        
        # Check if controller is installed
        if ! kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
            install_sealed_secrets_controller
        else
            echo "Sealed Secrets controller already installed"
        fi
        
        echo -e "${GREEN}Installation complete!${NC}"
        ;;
        
    create)
        create_sealed_secret "$2" "$3" "$4" "$5"
        ;;
        
    seal)
        seal_existing_secret "$2" "$3" "$4"
        ;;
        
    backup)
        backup_sealed_secrets_key
        ;;
        
    rotate)
        rotate_sealed_secrets_key
        ;;
        
    help|--help|-h)
        show_usage
        ;;
        
    *)
        echo -e "${RED}Invalid command: ${1:-}${NC}"
        show_usage
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}================================================${NC}"

# Additional examples
if [ "${1:-}" = "install" ]; then
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "1. Create a sealed secret:"
    echo "   $0 create db-password demo-app password 'mypass123'"
    echo ""
    echo "2. Apply the sealed secret:"
    echo "   kubectl apply -f clusters/production/apps/demo-app/db-password-sealed.yaml"
    echo ""
    echo "3. Verify the secret was created:"
    echo "   kubectl get secret db-password -n demo-app"
    echo ""
    echo "4. Backup encryption keys (important!):"
    echo "   $0 backup"
fi
