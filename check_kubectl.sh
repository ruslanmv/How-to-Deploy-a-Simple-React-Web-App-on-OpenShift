#!/bin/bash

# Script to interactively check the status and details of a Kubernetes/OpenShift deployment

# --- Colors for better UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Function to print messages ---
header() {
    echo -e "\n${BLUE}==================== $1 ====================${NC}"
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

prompt() {
    echo -e "${YELLOW}$1${NC}"
}

# --- Check for kubectl ---
if ! command -v kubectl &> /dev/null
then
    error "kubectl command could not be found. Please install kubectl and ensure it's in your PATH."
    exit 1
fi
info "kubectl found."

# --- Welcome Message ---
echo -e "${CYAN}==========================================================${NC}"
echo -e "${CYAN} Kubernetes/OpenShift Interactive Deployment Checker Script ${NC}"
echo -e "${CYAN}==========================================================${NC}"
echo

# --- Gather Information ---
prompt "Enter the application name of the deployment to check (e.g., hello-react):"
read -r APP_NAME
if [[ -z "$APP_NAME" ]]; then
    error "Application name cannot be empty."
    exit 1
fi

prompt "Enter the Kubernetes namespace where the application is deployed:"
read -r NAMESPACE
if [[ -z "$NAMESPACE" ]]; then
    CURRENT_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    if [[ -n "$CURRENT_NS" ]]; then
        NAMESPACE=$CURRENT_NS
        info "Using current kubectl context namespace: $NAMESPACE"
    else
        prompt "No current namespace found. Please enter a namespace:"
        read -r NAMESPACE
        while [[ -z "$NAMESPACE" ]]; do
            error "Namespace cannot be empty."
            prompt "Please enter a namespace:"
            read -r NAMESPACE
        done
    fi
fi

info "Checking deployment for application '$APP_NAME' in namespace '$NAMESPACE'..."

# --- Function to check if a resource exists ---
check_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local ns=$3
    kubectl get "$resource_type" "$resource_name" -n "$ns" &> /dev/null
    return $?
}

# --- Deployment Information ---
header "Deployment: $APP_NAME"
if check_resource_exists "deployment" "$APP_NAME" "$NAMESPACE"; then
    info "Getting Deployment details..."
    kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o wide
    echo -e "\n${CYAN}Describing Deployment '$APP_NAME':${NC}"
    kubectl describe deployment "$APP_NAME" -n "$NAMESPACE"
else
    warn "Deployment '$APP_NAME' not found in namespace '$NAMESPACE'."
fi

# --- Pods Information ---
header "Pods for Deployment: $APP_NAME"
info "Getting Pods associated with Deployment '$APP_NAME' (using label app=$APP_NAME)..."
# Construct the label selector based on common practice from deploy_kubectl.sh
# If your deploy script uses different primary labels for pod selection, adjust this.
POD_SELECTOR="app=$APP_NAME"
kubectl get pods -n "$NAMESPACE" -l "$POD_SELECTOR" -o wide

# Get specific pod names for logs and describe
POD_NAMES=$(kubectl get pods -n "$NAMESPACE" -l "$POD_SELECTOR" -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$POD_NAMES" ]]; then
    warn "No pods found with label '$POD_SELECTOR' for deployment '$APP_NAME'."
else
    for POD_NAME in $POD_NAMES; do
        header "Pod Details: $POD_NAME"
        echo -e "${CYAN}Describing Pod '$POD_NAME':${NC}"
        kubectl describe pod "$POD_NAME" -n "$NAMESPACE"
        
        echo -e "\n${CYAN}Recent logs for Pod '$POD_NAME' (last 50 lines):${NC}"
        kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=50
        
        # Option to view full logs
        prompt "Do you want to view full (streaming) logs for pod $POD_NAME? (yes/no, default: no)"
        read -r VIEW_FULL_LOGS
        if [[ "${VIEW_FULL_LOGS,,}" == "yes" ]]; then
            info "Streaming logs for $POD_NAME. Press Ctrl+C to stop."
            kubectl logs -f "$POD_NAME" -n "$NAMESPACE"
        fi
    done
fi

# --- Service Information ---
header "Service: $APP_NAME"
if check_resource_exists "service" "$APP_NAME" "$NAMESPACE"; then
    info "Getting Service details..."
    kubectl get service "$APP_NAME" -n "$NAMESPACE" -o wide
    
    echo -e "\n${CYAN}Describing Service '$APP_NAME':${NC}"
    kubectl describe service "$APP_NAME" -n "$NAMESPACE"

    header "Endpoints for Service: $APP_NAME"
    info "Getting Endpoints for Service '$APP_NAME'..."
    kubectl get endpoints "$APP_NAME" -n "$NAMESPACE"
else
    warn "Service '$APP_NAME' not found in namespace '$NAMESPACE'."
fi

# --- Route Information (OpenShift Specific) ---
header "Route: $APP_NAME (OpenShift Specific)"
# Check if Route CRD exists (simple check, might not be foolproof for all K8s distros)
if kubectl api-resources --api-group=route.openshift.io | grep -q routes; then
    if check_resource_exists "route" "$APP_NAME" "$NAMESPACE"; then
        info "Getting Route details..."
        kubectl get route "$APP_NAME" -n "$NAMESPACE" -o wide
        
        ROUTE_URL=$(kubectl get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
        if [[ -n "$ROUTE_URL" ]]; then
            # Check for TLS to determine protocol
            TLS_TERMINATION=$(kubectl get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.tls.termination}')
            if [[ -n "$TLS_TERMINATION" ]]; then
                ROUTE_URL="https://$ROUTE_URL"
            else
                ROUTE_URL="http://$ROUTE_URL"
            fi
            success "Application URL: $ROUTE_URL"
        else
            warn "Could not determine application URL from the Route."
        fi

        echo -e "\n${CYAN}Describing Route '$APP_NAME':${NC}"
        kubectl describe route "$APP_NAME" -n "$NAMESPACE"
    else
        warn "Route '$APP_NAME' not found in namespace '$NAMESPACE'."
        info "If this is not an OpenShift cluster, Routes are not applicable. Look for Ingress resources if applicable."
    fi
else
    info "Route CRD (route.openshift.io) not found. Skipping Route check. This is expected if not on OpenShift."
    info "For standard Kubernetes, you would typically check for an Ingress resource:"
    info "kubectl get ingress -n $NAMESPACE -l app=$APP_NAME" # Example, selector might vary
fi

echo -e "\n${CYAN}==================== Check Complete ====================${NC}"
exit 0
