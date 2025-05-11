#!/bin/bash

# Script to interactively gather information, build Kubernetes YAML files,
# and then deploy them using kubectl.

# --- Colors for better UX ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Function to print messages ---
header() {
    echo -e "\n${BLUE}====== $1 ======${NC}"
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
success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}
prompt() {
    # Prompt messages should not interpret escapes like \n, so no -e by default
    # If you need a newline in a prompt, embed it literally or use multiple prompt calls.
    echo -en "${YELLOW}$1${NC}" # -n to keep read on the same line
}

# --- Check for kubectl ---
if ! command -v kubectl &> /dev/null
then
    error "kubectl command could not be found. Please install kubectl and ensure it's in your PATH."
    exit 1
fi
info "kubectl found."

# --- Early Check for OpenShift Environment ---
IS_OPENSHIFT=false
info "Checking for OpenShift environment..."
# Silence stderr for the api-resources check as it can output "error: the server doesn't have resource type..." which is expected in non-OpenShift
if kubectl api-resources --api-group=route.openshift.io 2>/dev/null | grep -q -w "routes"; then
    IS_OPENSHIFT=true
    info "OpenShift environment detected (Route API available)."
else
    info "Standard Kubernetes environment detected (Route API not found)."
fi

# --- Welcome Message ---
echo -e "${CYAN}==============================================================${NC}"
echo -e "${CYAN} Kubernetes/OpenShift Interactive YAML Builder & Deployer Script ${NC}"
echo -e "${CYAN}==============================================================${NC}"
echo

# --- Gather Information ---
APP_NAME_DEFAULT="hello-react"
prompt "Enter the application name (e.g., my-react-app, default: $APP_NAME_DEFAULT): "
read -r APP_NAME
APP_NAME=${APP_NAME:-$APP_NAME_DEFAULT}

DOCKER_IMAGE_DEFAULT="docker.io/ruslanmv/hello-react:1.0.0"
prompt "Enter the Docker image (e.g., nginx:latest, default: $DOCKER_IMAGE_DEFAULT): "
read -r DOCKER_IMAGE
DOCKER_IMAGE=${DOCKER_IMAGE:-$DOCKER_IMAGE_DEFAULT}

NAMESPACE_DEFAULT="ibmid-667000nwl8-hktijvj4" # Default from your example
prompt "Enter the Kubernetes namespace to deploy to (e.g., my-namespace, default: $NAMESPACE_DEFAULT): "
read -r NAMESPACE
if [[ -z "$NAMESPACE" ]]; then
    CURRENT_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    if [[ -n "$CURRENT_NS" ]] && [[ "$CURRENT_NS" != "null" ]] && [[ "$CURRENT_NS" != "<nil>" ]]; then # Check if current namespace is set and not literal "null" or "<nil>"
        NAMESPACE=$CURRENT_NS
        info "Using current kubectl context namespace: $NAMESPACE"
    else
        NAMESPACE=$NAMESPACE_DEFAULT
        info "Using default namespace: $NAMESPACE"
    fi
fi


CONTAINER_PORT_DEFAULT="8080"
prompt "Enter the container port your application listens on (e.g., 80, default: $CONTAINER_PORT_DEFAULT): "
read -r CONTAINER_PORT
CONTAINER_PORT=${CONTAINER_PORT:-$CONTAINER_PORT_DEFAULT}
if ! [[ "$CONTAINER_PORT" =~ ^[0-9]+$ ]] || [[ "$CONTAINER_PORT" -lt 1 ]] || [[ "$CONTAINER_PORT" -gt 65535 ]]; then
    error "Invalid port number. Please enter a numeric value between 1 and 65535."
    exit 1
fi

REPLICAS_DEFAULT="1"
prompt "Enter the number of replicas (e.g., 1, default: $REPLICAS_DEFAULT): "
read -r REPLICAS
REPLICAS=${REPLICAS:-$REPLICAS_DEFAULT}
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [[ "$REPLICAS" -lt 1 ]]; then
    error "Invalid number of replicas. Must be a positive integer."
    exit 1
fi

header "Resource Allocation"
# Defaults matching user's desired "should be" deployment.yaml
CPU_REQUEST_DEFAULT="1" # Can be "1" or "1000m"
CPU_LIMIT_DEFAULT="2"   # Can be "2" or "2000m"
MEMORY_REQUEST_DEFAULT="128Mi"
MEMORY_LIMIT_DEFAULT="256Mi"

prompt "Enter CPU request for the container (e.g., 1, 500m, default: ${CPU_REQUEST_DEFAULT}): "
read -r CPU_REQUEST
CPU_REQUEST=${CPU_REQUEST:-$CPU_REQUEST_DEFAULT}

prompt "Enter CPU limit for the container (e.g., 2, 1000m, default: ${CPU_LIMIT_DEFAULT}): "
read -r CPU_LIMIT
CPU_LIMIT=${CPU_LIMIT:-$CPU_LIMIT_DEFAULT}

prompt "Enter Memory request for the container (e.g., 128Mi, default: ${MEMORY_REQUEST_DEFAULT}): "
read -r MEMORY_REQUEST
MEMORY_REQUEST=${MEMORY_REQUEST:-$MEMORY_REQUEST_DEFAULT}

prompt "Enter Memory limit for the container (e.g., 256Mi, default: ${MEMORY_LIMIT_DEFAULT}): "
read -r MEMORY_LIMIT
MEMORY_LIMIT=${MEMORY_LIMIT:-$MEMORY_LIMIT_DEFAULT}

# Service port will be named, e.g., http-8080, for the Route to reference
SERVICE_PORT_NAME="http-${CONTAINER_PORT}"

prompt "Enter the directory to save YAML files (default: ./${APP_NAME}-kube-config): "
read -r OUTPUT_DIR
OUTPUT_DIR=${OUTPUT_DIR:-./${APP_NAME}-kube-config}

# --- Define Label Blocks ---
# Common labels for metadata.labels sections of Deployment, Service, Route
# Each line must be indented with 4 spaces to be correctly placed under 'labels:'
_common_labels_content="    app: ${APP_NAME}
    app.kubernetes.io/component: ${APP_NAME}
    app.kubernetes.io/instance: ${APP_NAME}
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/part-of: ${APP_NAME}-app"

if [[ "$IS_OPENSHIFT" == true ]]; then
    # Append the OpenShift label on a new line, correctly indented
    _common_labels_content+=$(printf "\n    app.openshift.io/runtime-version: \"%s\"" "1.0.0")
fi
COMMON_LABELS_BLOCK="$_common_labels_content"


# Labels for Deployment spec.selector.matchLabels
# These are indented relative to 'selector:'
# The string itself contains the necessary indentation.
SELECTOR_MATCH_LABELS_BLOCK="    matchLabels:
      app: $APP_NAME"

# Labels for Deployment spec.template.metadata.labels
# These are indented relative to 'template.metadata:'
# The string itself contains the necessary indentation.
POD_TEMPLATE_LABELS_BLOCK="    metadata:
      labels:
        app: $APP_NAME
        deployment: $APP_NAME"

# --- Summary of inputs ---
header "Configuration Summary"
echo -e "Application Name: ${GREEN}$APP_NAME${NC}"
echo -e "Docker Image:     ${GREEN}$DOCKER_IMAGE${NC}"
echo -e "Namespace:        ${GREEN}$NAMESPACE${NC}"
echo -e "Container Port:   ${GREEN}$CONTAINER_PORT${NC}"
echo -e "Service Port Name:${GREEN}$SERVICE_PORT_NAME${NC} (for Service and Route)"
echo -e "Replicas:         ${GREEN}$REPLICAS${NC}"
echo -e "CPU Request:      ${GREEN}$CPU_REQUEST${NC}, CPU Limit: ${GREEN}$CPU_LIMIT${NC}"
echo -e "Memory Request:   ${GREEN}$MEMORY_REQUEST${NC}, Memory Limit: ${GREEN}$MEMORY_LIMIT${NC}"
echo -e "Output Directory: ${GREEN}$OUTPUT_DIR${NC}"
echo -e "Common Labels (for Deployment, Service, Route metadata.labels):"
# For display, remove the first 2 spaces from each line of COMMON_LABELS_BLOCK to align under the title
echo -e "${GREEN}$(echo "$COMMON_LABELS_BLOCK" | sed 's/^  //')${NC}"
echo -e "Selector Match Labels (for Deployment spec.selector):"
# Display as is, assuming its formatting is relative and understandable in context
echo -e "${GREEN}${SELECTOR_MATCH_LABELS_BLOCK}${NC}"
echo -e "Pod Template Labels (for Deployment spec.template.metadata.labels):"
# Display as is for pod template labels
echo -e "${GREEN}${POD_TEMPLATE_LABELS_BLOCK}${NC}"
echo

# --- Confirm generation of YAML files ---
prompt "The script will generate YAML files for Deployment, Service, and potentially Route (OpenShift).
Do you want to proceed with generating these YAML files in '$OUTPUT_DIR'? (yes/no): "
read -r CONFIRM_GENERATE
if [[ "${CONFIRM_GENERATE,,}" != "yes" ]]; then
    info "YAML generation aborted by user."
    exit 0
fi

if mkdir -p "$OUTPUT_DIR"; then
    success "Output directory '$OUTPUT_DIR' ensured."
else
    error "Failed to create output directory '$OUTPUT_DIR'. Please check permissions."
    exit 1
fi

# --- Deployment YAML ---
DEPLOYMENT_FILE_PATH="${OUTPUT_DIR}/${APP_NAME}-deployment.yaml"
# Note: COMMON_LABELS_BLOCK is inserted directly after 'labels:'
# The content of COMMON_LABELS_BLOCK is already indented with 4 spaces.
DEPLOYMENT_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
${COMMON_LABELS_BLOCK}
spec:
  replicas: $REPLICAS
  selector:
${SELECTOR_MATCH_LABELS_BLOCK}
  template:
${POD_TEMPLATE_LABELS_BLOCK}
    spec:
      containers:
        - name: $APP_NAME
          image: $DOCKER_IMAGE
          ports:
            - containerPort: $CONTAINER_PORT # Unnamed as per desired output
              protocol: TCP
          resources:
            requests:
              cpu: "$CPU_REQUEST"
              memory: "$MEMORY_REQUEST"
            limits:
              cpu: "$CPU_LIMIT"
              memory: "$MEMORY_LIMIT"
          imagePullPolicy: IfNotPresent
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      securityContext: {} # Added as per user's desired output
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
EOF
)
echo "$DEPLOYMENT_YAML" > "$DEPLOYMENT_FILE_PATH"
success "Generated $DEPLOYMENT_FILE_PATH"

# --- Service YAML ---
SERVICE_FILE_PATH="${OUTPUT_DIR}/${APP_NAME}-service.yaml"
SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
${COMMON_LABELS_BLOCK}
spec:
  selector:
    app: $APP_NAME # Selector for pods
  ports:
    - name: $SERVICE_PORT_NAME # Service port is named
      protocol: TCP
      port: $CONTAINER_PORT # Service listens on this port
      targetPort: $CONTAINER_PORT # Targets the container's port number
  type: ClusterIP
EOF
)
echo "$SERVICE_YAML" > "$SERVICE_FILE_PATH"
success "Generated $SERVICE_FILE_PATH"

# --- Route YAML (OpenShift Specific) ---
ROUTE_FILE_PATH="" # Initialize to empty
if [[ "$IS_OPENSHIFT" == true ]]; then
    ROUTE_FILE_PATH="${OUTPUT_DIR}/${APP_NAME}-route.yaml"
    ROUTE_YAML=$(cat <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
${COMMON_LABELS_BLOCK}
  annotations:
    openshift.io/host.generated: "true"
spec:
  to:
    kind: Service
    name: $APP_NAME
    weight: 100
  port:
    targetPort: $SERVICE_PORT_NAME # Must match the Service's named port
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
)
    echo "$ROUTE_YAML" > "$ROUTE_FILE_PATH"
    success "Generated $ROUTE_FILE_PATH (OpenShift Route)"
else
    info "Skipping OpenShift Route generation as it's not an OpenShift environment."
    warn "If deploying to standard Kubernetes and need external access, create an Ingress resource manually."
fi
echo

# --- Confirm Deployment ---
info "YAML files have been generated in '$OUTPUT_DIR'."
prompt "Do you want to deploy these generated files to namespace '$NAMESPACE' now? (yes/no): "
read -r CONFIRM_DEPLOY
if [[ "${CONFIRM_DEPLOY,,}" != "yes" ]]; then
    info "Deployment aborted by user. You can deploy the files manually using 'kubectl apply -f <file_path>'."
    exit 0
fi

# --- Apply configurations ---
header "Deployment Process"

# Check if namespace exists, create if it doesn't after confirmation
if ! kubectl get namespace "$NAMESPACE" --output=name &> /dev/null; then
    prompt "Namespace '$NAMESPACE' does not exist. Do you want to create it? (yes/no): "
    read -r CREATE_NS_CONFIRM
    if [[ "${CREATE_NS_CONFIRM,,}" == "yes" ]]; then
        if kubectl create namespace "$NAMESPACE"; then
            success "Namespace '$NAMESPACE' created."
        else
            error "Failed to create namespace '$NAMESPACE'. Please check permissions or create it manually."
            exit 1
        fi
    else
        error "Namespace '$NAMESPACE' does not exist and creation was declined. Aborting deployment."
        exit 1
    fi
else
    info "Namespace '$NAMESPACE' already exists."
fi
echo

info "Applying Deployment ($DEPLOYMENT_FILE_PATH)..."
if kubectl apply -f "$DEPLOYMENT_FILE_PATH"; then
    success "Deployment applied/configured."
else
    error "Failed to apply Deployment from $DEPLOYMENT_FILE_PATH."
    # Consider exiting, or allowing the script to try applying other resources
    # For now, exit on critical failure.
    exit 1
fi
echo

info "Applying Service ($SERVICE_FILE_PATH)..."
if kubectl apply -f "$SERVICE_FILE_PATH"; then
    success "Service applied/configured."
else
    error "Failed to apply Service from $SERVICE_FILE_PATH."
    exit 1
fi
echo

if [[ "$IS_OPENSHIFT" == true ]] && [[ -n "$ROUTE_FILE_PATH" ]]; then
    info "Applying Route ($ROUTE_FILE_PATH)..."
    if kubectl apply -f "$ROUTE_FILE_PATH"; then
        success "Route applied/configured."
    else
        error "Failed to apply Route from $ROUTE_FILE_PATH."
        # Not exiting here, as route might be less critical for some workflows
    fi
    echo
fi

# --- Post-deployment Information ---
success "All selected configurations applied!"
echo
info "You can check the status of your deployment with the following commands:"
echo -e "  ${YELLOW}kubectl get deployments -n $NAMESPACE${NC}"
echo -e "  ${YELLOW}kubectl get pods -n $NAMESPACE -w${NC}"
echo -e "  ${YELLOW}kubectl get services -n $NAMESPACE${NC}"
if [[ "$IS_OPENSHIFT" == true ]]; then
    echo -e "  ${YELLOW}kubectl get routes -n $NAMESPACE${NC}"
    ROUTE_HOST=$(kubectl get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
    if [[ -n "$ROUTE_HOST" ]]; then
        echo -e "  Access your application (once ready) via: ${GREEN}http://${ROUTE_HOST}${NC} or ${GREEN}https://${ROUTE_HOST}${NC}"
    fi
fi
echo -e "  ${YELLOW}kubectl logs -f deployment/$APP_NAME -n $NAMESPACE${NC}"
echo -e "  ${YELLOW}Use './check_kubectl.sh' (if available) for a detailed status check.${NC}" # Assuming check_kubectl.sh is a separate script
echo
info "It might take a few moments for the pods to be ready and the route (if applicable) to be active."
echo -e "${CYAN}==============================================================${NC}"

exit 0