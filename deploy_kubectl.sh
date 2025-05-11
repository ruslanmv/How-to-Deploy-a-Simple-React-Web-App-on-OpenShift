#!/bin/bash

# Script to interactively deploy a Docker container using kubectl

# --- Colors for better UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Function to print messages ---
info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
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
echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN} Kubernetes/OpenShift Interactive Deployment Script ${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo

# --- Gather Information ---
prompt "Enter the application name (e.g., my-react-app):"
read -r APP_NAME
APP_NAME=${APP_NAME:-hello-react} # Default if empty

prompt "Enter the Docker image (e.g., docker.io/ruslanmv/hello-react:1.0.0):"
read -r DOCKER_IMAGE
DOCKER_IMAGE=${DOCKER_IMAGE:-docker.io/ruslanmv/hello-react:1.0.0} # Default if empty

prompt "Enter the Kubernetes namespace to deploy to (e.g., my-namespace):"
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

prompt "Enter the container port your application listens on (e.g., 8080):"
read -r CONTAINER_PORT
CONTAINER_PORT=${CONTAINER_PORT:-8080} # Default if empty
# Validate port is a number
if ! [[ "$CONTAINER_PORT" =~ ^[0-9]+$ ]]; then
    error "Invalid port number. Please enter a numeric value."
    exit 1
fi

prompt "Enter the number of replicas (e.g., 1):"
read -r REPLICAS
REPLICAS=${REPLICAS:-1} # Default if empty
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [[ "$REPLICAS" -lt 1 ]]; then
    error "Invalid number of replicas. Must be a positive integer."
    exit 1
fi

prompt "Enter CPU request for the container (e.g., 100m for 0.1 CPU, default: 250m):"
read -r CPU_REQUEST
CPU_REQUEST=${CPU_REQUEST:-250m}

prompt "Enter CPU limit for the container (e.g., 500m for 0.5 CPU, default: 500m):"
read -r CPU_LIMIT
CPU_LIMIT=${CPU_LIMIT:-500m}

prompt "Enter Memory request for the container (e.g., 128Mi, default: 128Mi):"
read -r MEMORY_REQUEST
MEMORY_REQUEST=${MEMORY_REQUEST:-128Mi}

prompt "Enter Memory limit for the container (e.g., 256Mi, default: 256Mi):"
read -r MEMORY_LIMIT
MEMORY_LIMIT=${MEMORY_LIMIT:-256Mi}

SERVICE_PORT_NAME="http-${CONTAINER_PORT}" # Name for the service port

# --- Define Labels ---
# These labels will be used across all resources for consistency
declare -A LABELS
LABELS["app.kubernetes.io/name"]="$APP_NAME"
LABELS["app.kubernetes.io/instance"]="$APP_NAME"
LABELS["app.kubernetes.io/version"]="1.0.0" # You might want to make this dynamic or configurable
LABELS["app.kubernetes.io/component"]="frontend" # Example component
LABELS["app.kubernetes.io/part-of"]="$APP_NAME-app" # Example part-of
LABELS["app"]="$APP_NAME" # Simpler label for selectors

# Convert labels associative array to YAML string format for metadata
METADATA_LABELS_YAML=""
for key in "${!LABELS[@]}"; do
  METADATA_LABELS_YAML+="  $key: ${LABELS[$key]}\n"
done

# Selector labels for service and deployment
SELECTOR_LABELS_YAML="  app: $APP_NAME"


# --- Summary ---
echo
echo -e "${CYAN}-------------------- Deployment Summary --------------------${NC}"
echo -e "Application Name: ${GREEN}$APP_NAME${NC}"
echo -e "Docker Image:     ${GREEN}$DOCKER_IMAGE${NC}"
echo -e "Namespace:        ${GREEN}$NAMESPACE${NC}"
echo -e "Container Port:   ${GREEN}$CONTAINER_PORT${NC}"
echo -e "Service Port Name:${GREEN}$SERVICE_PORT_NAME${NC} (exposing container port ${CONTAINER_PORT})"
echo -e "Replicas:         ${GREEN}$REPLICAS${NC}"
echo -e "CPU Request:      ${GREEN}$CPU_REQUEST${NC}"
echo -e "CPU Limit:        ${GREEN}$CPU_LIMIT${NC}"
echo -e "Memory Request:   ${GREEN}$MEMORY_REQUEST${NC}"
echo -e "Memory Limit:     ${GREEN}$MEMORY_LIMIT${NC}"
echo -e "${CYAN}----------------------------------------------------------${NC}"
echo
echo -e "The following Kubernetes/OpenShift resources will be configured:"
echo -e "1. ${GREEN}Deployment${NC}: Manages the application pods."
echo -e "2. ${GREEN}Service${NC}: Exposes the application internally within the cluster."
echo -e "3. ${GREEN}Route${NC} (OpenShift specific): Exposes the application externally via a URL."
warn "The 'Route' resource is specific to OpenShift. If you are on a standard Kubernetes cluster, you might need an 'Ingress' resource instead, which requires an Ingress controller to be set up."
echo

prompt "Do you want to proceed with the deployment? (yes/no):"
read -r CONFIRMATION
if [[ "${CONFIRMATION,,}" != "yes" ]]; then
    info "Deployment aborted by user."
    exit 0
fi

# --- Deployment YAML ---
DEPLOYMENT_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
$(echo -e "$METADATA_LABELS_YAML" | sed 's/^/    /')
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
$(echo -e "$SELECTOR_LABELS_YAML" | sed 's/^/      /')
  template:
    metadata:
      labels:
$(echo -e "$SELECTOR_LABELS_YAML" | sed 's/^/        /')
$(echo -e "$METADATA_LABELS_YAML" | sed 's/^/        /')
    spec:
      containers:
        - name: $APP_NAME
          image: $DOCKER_IMAGE
          ports:
            - name: $SERVICE_PORT_NAME # Port name should match service targetPort name
              containerPort: $CONTAINER_PORT
              protocol: TCP
          resources:
            requests:
              cpu: "$CPU_REQUEST"
              memory: "$MEMORY_REQUEST"
            limits:
              cpu: "$CPU_LIMIT"
              memory: "$MEMORY_LIMIT"
          imagePullPolicy: IfNotPresent # Or "Always" to force pull
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      schedulerName: default-scheduler
EOF
)

# --- Service YAML ---
SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
$(echo -e "$METADATA_LABELS_YAML" | sed 's/^/    /')
spec:
  selector:
$(echo -e "$SELECTOR_LABELS_YAML" | sed 's/^/    /')
  ports:
    - name: $SERVICE_PORT_NAME # Name of the port
      protocol: TCP
      port: $CONTAINER_PORT       # Port the service will listen on (can be different from targetPort)
      targetPort: $SERVICE_PORT_NAME # Target port on the pod (references the containerPort name)
  type: ClusterIP # Default, or use NodePort/LoadBalancer if needed for non-OpenShift external access
EOF
)

# --- Route YAML (OpenShift Specific) ---
ROUTE_YAML=$(cat <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
$(echo -e "$METADATA_LABELS_YAML" | sed 's/^/    /')
  annotations:
    openshift.io/host.generated: "true" # Let OpenShift generate the hostname
spec:
  to:
    kind: Service
    name: $APP_NAME # Must match the Service name
    weight: 100
  port:
    targetPort: $SERVICE_PORT_NAME # Must match the Service port name
  tls:
    termination: edge # Common setting
    insecureEdgeTerminationPolicy: Redirect # Redirect HTTP to HTTPS
  wildcardPolicy: None
EOF
)

# --- Apply configurations ---
info "Applying Deployment..."
echo "$DEPLOYMENT_YAML" | kubectl apply -f -
if [ $? -ne 0 ]; then
    error "Failed to apply Deployment."
    exit 1
else
    success "Deployment applied/configured."
fi
echo

info "Applying Service..."
echo "$SERVICE_YAML" | kubectl apply -f -
if [ $? -ne 0 ]; then
    error "Failed to apply Service."
    exit 1
else
    success "Service applied/configured."
fi
echo

info "Applying Route (OpenShift specific)..."
echo "$ROUTE_YAML" | kubectl apply -f -
if [ $? -ne 0 ]; then
    error "Failed to apply Route. This might be expected if not on OpenShift or if Route CRD is not available."
    warn "If you are not on OpenShift, you may need to create an Ingress resource manually."
else
    success "Route applied/configured."
fi
echo

# --- Post-deployment Information ---
success "All configurations applied!"
echo
info "You can check the status of your deployment with the following commands:"
echo -e "  ${YELLOW}kubectl get deployments -n $NAMESPACE${NC}"
echo -e "  ${YELLOW}kubectl get pods -n $NAMESPACE -w${NC} (add -w to watch)"
echo -e "  ${YELLOW}kubectl get services -n $NAMESPACE${NC}"
echo -e "  ${YELLOW}kubectl get routes -n $NAMESPACE${NC} (for OpenShift, to find the URL)"
echo -e "  ${YELLOW}kubectl logs -f deployment/$APP_NAME -n $NAMESPACE${NC} (to see application logs)"
echo
info "It might take a few moments for the pods to be ready and the route to be active."
echo -e "${CYAN}=====================================================${NC}"

exit 0
