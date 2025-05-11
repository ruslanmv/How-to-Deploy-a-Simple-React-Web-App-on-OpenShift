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
header()   { echo -e "\n${BLUE}====== $1 ======${NC}"; }
info()     { echo -e "${CYAN}[INFO] $1${NC}"; }
warn()     { echo -e "${YELLOW}[WARN] $1${NC}"; }
error()    { echo -e "${RED}[ERROR] $1${NC}"; }
success()  { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
prompt()   { echo -e "${YELLOW}$1${NC}"; }

# --- Check for kubectl ---
if ! command -v kubectl &> /dev/null; then
  error "kubectl not found. Please install it and ensure it's in your PATH."
  exit 1
fi
info "kubectl found."

# --- Detect OpenShift ---
IS_OPENSHIFT=false
info "Checking for OpenShift environment..."
if kubectl api-resources --api-group=route.openshift.io | grep -q -w "routes"; then
  IS_OPENSHIFT=true
  info "OpenShift environment detected."
else
  info "Standard Kubernetes environment detected."
fi

# --- Welcome ---
echo -e "${CYAN}==============================================================${NC}"
echo -e "${CYAN} Kubernetes/OpenShift Interactive YAML Builder & Deployer Script ${NC}"
echo -e "${CYAN}==============================================================${NC}"

# --- Gather inputs with defaults ---
APP_NAME_DEFAULT="hello-react"
prompt "Enter the application name (default: $APP_NAME_DEFAULT):"
read -r APP_NAME; APP_NAME=${APP_NAME:-$APP_NAME_DEFAULT}

DOCKER_IMAGE_DEFAULT="docker.io/ruslanmv/hello-react:1.0.0"
prompt "Enter the Docker image (default: $DOCKER_IMAGE_DEFAULT):"
read -r DOCKER_IMAGE; DOCKER_IMAGE=${DOCKER_IMAGE:-$DOCKER_IMAGE_DEFAULT}

NAMESPACE_DEFAULT="ibmid-667000nwl8-hktijvj4"
prompt "Enter the Kubernetes namespace (default: $NAMESPACE_DEFAULT):"
read -r NAMESPACE
if [[ -z "$NAMESPACE" ]]; then
  CURRENT_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}')
  if [[ -n "$CURRENT_NS" ]]; then
    NAMESPACE=$CURRENT_NS
    info "Using current context namespace: $NAMESPACE"
  else
    NAMESPACE=$NAMESPACE_DEFAULT
    info "Using default namespace: $NAMESPACE"
  fi
fi

CONTAINER_PORT_DEFAULT="8080"
prompt "Enter the container port (default: $CONTAINER_PORT_DEFAULT):"
read -r CONTAINER_PORT; CONTAINER_PORT=${CONTAINER_PORT:-$CONTAINER_PORT_DEFAULT}
if ! [[ "$CONTAINER_PORT" =~ ^[0-9]+$ ]] || (( CONTAINER_PORT<1 || CONTAINER_PORT>65535 )); then
  error "Port must be a number between 1 and 65535."
  exit 1
fi

REPLICAS_DEFAULT="1"
prompt "Enter number of replicas (default: $REPLICAS_DEFAULT):"
read -r REPLICAS; REPLICAS=${REPLICAS:-$REPLICAS_DEFAULT}
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || (( REPLICAS<1 )); then
  error "Replicas must be a positive integer."
  exit 1
fi

header "Resource Allocation"
CPU_REQUEST_DEFAULT="1"
CPU_LIMIT_DEFAULT="2"
MEMORY_REQUEST_DEFAULT="128Mi"
MEMORY_LIMIT_DEFAULT="256Mi"

prompt "CPU request (default: $CPU_REQUEST_DEFAULT):"
read -r CPU_REQUEST; CPU_REQUEST=${CPU_REQUEST:-$CPU_REQUEST_DEFAULT}
prompt "CPU limit (default: $CPU_LIMIT_DEFAULT):"
read -r CPU_LIMIT; CPU_LIMIT=${CPU_LIMIT:-$CPU_LIMIT_DEFAULT}
prompt "Memory request (default: $MEMORY_REQUEST_DEFAULT):"
read -r MEMORY_REQUEST; MEMORY_REQUEST=${MEMORY_REQUEST:-$MEMORY_REQUEST_DEFAULT}
prompt "Memory limit (default: $MEMORY_LIMIT_DEFAULT):"
read -r MEMORY_LIMIT; MEMORY_LIMIT=${MEMORY_LIMIT:-$MEMORY_LIMIT_DEFAULT}

SERVICE_PORT_NAME="http-${CONTAINER_PORT}"

prompt "Directory to save YAML files (default: ./${APP_NAME}-kube-config):"
read -r OUTPUT_DIR; OUTPUT_DIR=${OUTPUT_DIR:-./${APP_NAME}-kube-config}

# --- Build label array ---
common_labels=(
  "app: $APP_NAME"
  "app.kubernetes.io/component: $APP_NAME"
  "app.kubernetes.io/instance: $APP_NAME"
  "app.kubernetes.io/name: $APP_NAME"
  "app.kubernetes.io/part-of: ${APP_NAME}-app"
)

# --- Show summary ---
header "Configuration Summary"
echo -e "Application Name: ${GREEN}$APP_NAME${NC}"
echo -e "Docker Image:     ${GREEN}$DOCKER_IMAGE${NC}"
echo -e "Namespace:        ${GREEN}$NAMESPACE${NC}"
echo -e "Container Port:   ${GREEN}$CONTAINER_PORT${NC}"
echo -e "Service Port Name:${GREEN}$SERVICE_PORT_NAME${NC}"
echo -e "Replicas:         ${GREEN}$REPLICAS${NC}"
echo -e "CPU Request/Limit:   ${GREEN}$CPU_REQUEST / $CPU_LIMIT${NC}"
echo -e "Memory Request/Limit:${GREEN}$MEMORY_REQUEST / $MEMORY_LIMIT${NC}"
echo -e "Output Directory: ${GREEN}$OUTPUT_DIR${NC}"
echo -e "${CYAN}==============================================================${NC}"

prompt "Generate YAML files in '$OUTPUT_DIR'? (yes/no):"
read -r CONFIRM; [[ "${CONFIRM,,}" == "yes" ]] || { info "Aborted."; exit 0; }

mkdir -p "$OUTPUT_DIR" && success "Directory '$OUTPUT_DIR' ready." || { error "Cannot create '$OUTPUT_DIR'."; exit 1; }

# --- Deployment YAML ---
DEPLOYMENT_FILE="$OUTPUT_DIR/${APP_NAME}-deployment.yaml"
cat > "$DEPLOYMENT_FILE" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
EOF
for lbl in "${common_labels[@]}"; do
  printf '    %s\n' "$lbl" >> "$DEPLOYMENT_FILE"
done
cat >> "$DEPLOYMENT_FILE" <<EOF
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
        deployment: $APP_NAME
    spec:
      containers:
        - name: $APP_NAME
          image: $DOCKER_IMAGE
          ports:
            - containerPort: $CONTAINER_PORT
              protocol: TCP
          resources:
            limits:
              cpu: '$CPU_LIMIT'
              memory: $MEMORY_LIMIT
            requests:
              cpu: '$CPU_REQUEST'
              memory: $MEMORY_REQUEST
          imagePullPolicy: IfNotPresent
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      securityContext: {}
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
EOF
success "Generated $DEPLOYMENT_FILE"

# --- Service YAML ---
SERVICE_FILE="$OUTPUT_DIR/${APP_NAME}-service.yaml"
cat > "$SERVICE_FILE" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
EOF
for lbl in "${common_labels[@]}"; do
  printf '    %s\n' "$lbl" >> "$SERVICE_FILE"
done
cat >> "$SERVICE_FILE" <<EOF
spec:
  selector:
    app: $APP_NAME
  ports:
    - name: $SERVICE_PORT_NAME
      protocol: TCP
      port: $CONTAINER_PORT
      targetPort: $CONTAINER_PORT
  type: ClusterIP
EOF
success "Generated $SERVICE_FILE"

# --- Route YAML (OpenShift) ---
if [[ "$IS_OPENSHIFT" == true ]]; then
  ROUTE_FILE="$OUTPUT_DIR/${APP_NAME}-route.yaml"
  cat > "$ROUTE_FILE" <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
EOF
  for lbl in "${common_labels[@]}"; do
    printf '    %s\n' "$lbl" >> "$ROUTE_FILE"
  done
  printf '    app.openshift.io/runtime-version: "1.0.0"\n' >> "$ROUTE_FILE"
  cat >> "$ROUTE_FILE" <<EOF
  annotations:
    openshift.io/host.generated: "true"
spec:
  to:
    kind: Service
    name: $APP_NAME
    weight: 100
  port:
    targetPort: $SERVICE_PORT_NAME
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
  success "Generated $ROUTE_FILE (OpenShift Route)"
else
  info "Skipping Route (not OpenShift)."
  warn "If you need external access on vanilla Kubernetes, create an Ingress yourself."
fi

info "YAML files are in '$OUTPUT_DIR'."
prompt "Deploy to namespace '$NAMESPACE' now? (yes/no):"
read -r CONF2; [[ "${CONF2,,}" == "yes" ]] || { info "Done — you can apply them manually."; exit 0; }

# --- Deployment process ---
header "Deployment Process"
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
  prompt "Namespace '$NAMESPACE' missing. Create it? (yes/no):"
  read -r C; [[ "${C,,}" == "yes" ]] && kubectl create namespace "$NAMESPACE" && success "Namespace created." || { error "Namespace absent — abort."; exit 1; }
else
  info "Namespace '$NAMESPACE' exists."
fi

info "Applying Deployment..."
kubectl apply -f "$DEPLOYMENT_FILE" && success "Deployment applied." || exit 1
info "Applying Service..."
kubectl apply -f "$SERVICE_FILE" && success "Service applied." || exit 1

if [[ "$IS_OPENSHIFT" == true ]]; then
  info "Applying Route..."
  kubectl apply -f "$ROUTE_FILE" && success "Route applied." || warn "Route apply failed."
fi

success "All resources applied!"
echo -e "
You can check status with:
  kubectl get deployments,svc,pods -n $NAMESPACE
  kubectl logs -f deployment/$APP_NAME -n $NAMESPACE
"
exit 0
