#!/bin/bash

# Kubeflow Pipelines Installation v2
# Simplified installation using platform-agnostic deployment with SQLite

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Kubeflow Pipelines Installation v2${NC}"
echo -e "${GREEN}================================================${NC}"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed.${NC}"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Not connected to Kubernetes cluster.${NC}"
    exit 1
fi

# Step 1: Clean up any existing installation
echo -e "\n${YELLOW}Step 1: Cleaning up existing installation...${NC}"
kubectl delete namespace kubeflow --ignore-not-found=true --wait=false 2>/dev/null || true
echo "→ Waiting for namespace deletion (this may take a minute)..."
while kubectl get namespace kubeflow &>/dev/null; do
    echo -n "."
    sleep 2
done
echo " Done!"

# Clean up CRDs
kubectl delete crd -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true

# Step 2: Create namespace
echo -e "\n${YELLOW}Step 2: Creating namespace...${NC}"
kubectl create namespace kubeflow

# Step 3: Install Kubeflow Pipelines
echo -e "\n${YELLOW}Step 3: Installing Kubeflow Pipelines...${NC}"
echo "→ Using platform-agnostic deployment..."

# Apply the manifests (warnings are from upstream and can be ignored)
export PIPELINE_VERSION=2.0.5
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION" 2>&1 | \
    grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true

# Wait for CRDs
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io 2>/dev/null || true

# Apply platform-agnostic deployment
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION" 2>&1 | \
    grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true

# Step 4: Wait and configure for SQLite
echo -e "\n${YELLOW}Step 4: Configuring for SQLite backend...${NC}"
echo "→ Waiting for deployments to be created..."
sleep 15

# Check if ml-pipeline deployment exists
if kubectl get deployment ml-pipeline -n kubeflow &>/dev/null; then
    echo "→ Patching ml-pipeline for SQLite..."
    kubectl patch deployment ml-pipeline -n kubeflow --type='json' -p='[
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "DBCONFIG_DRIVER", "value": "sqlite3"}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "DBCONFIG_DB_NAME", "value": "/var/mlpipeline/mlpipeline.db"}},
        {"op": "add", "path": "/spec/template/spec/volumes", "value": [{"name": "mlpipeline-db", "emptyDir": {}}]},
        {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts", "value": [{"name": "mlpipeline-db", "mountPath": "/var/mlpipeline"}]}
    ]' 2>/dev/null || {
        echo "  Patch failed, applying override deployment..."
        kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-pipeline
  namespace: kubeflow
spec:
  selector:
    matchLabels:
      app: ml-pipeline
  template:
    metadata:
      labels:
        app: ml-pipeline
    spec:
      serviceAccountName: ml-pipeline
      containers:
      - name: ml-pipeline-api-server
        image: gcr.io/ml-pipeline/api-server:2.0.5
        env:
        - name: DBCONFIG_DRIVER
          value: sqlite3
        - name: DBCONFIG_DB_NAME
          value: /var/mlpipeline/mlpipeline.db
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: mlpipeline-db
          mountPath: /var/mlpipeline
        ports:
        - containerPort: 8888
        - containerPort: 8887
      volumes:
      - name: mlpipeline-db
        emptyDir: {}
EOF
    }
fi

# Step 5: Fix Minio if needed
echo -e "\n${YELLOW}Step 5: Checking Minio...${NC}"

# First, delete any existing minio deployment to avoid selector conflicts
kubectl delete deployment minio -n kubeflow --ignore-not-found=true 2>/dev/null
kubectl delete service minio-service -n kubeflow --ignore-not-found=true 2>/dev/null
sleep 5

# Now deploy fresh minio
echo "→ Deploying Minio for artifact storage..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: kubeflow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        env:
        - name: MINIO_ROOT_USER
          value: minio
        - name: MINIO_ROOT_PASSWORD
          value: minio123
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  namespace: kubeflow
spec:
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: minio
EOF

# Step 6: Port forward script
echo -e "\n${YELLOW}Step 6: Creating port forward script...${NC}"
cat > port_forward_v2.sh << 'EOF'
#!/bin/bash
echo "Starting Kubeflow Pipelines UI port forward..."
echo "Access at: http://localhost:8080"
echo "Press Ctrl+C to stop"
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
EOF
chmod +x port_forward_v2.sh

# Final status
echo -e "\n${YELLOW}Checking deployment status...${NC}"
echo "→ Waiting for pods to start (this may take 2-3 minutes)..."
sleep 10

echo ""
echo "Current pod status:"
kubectl get pods -n kubeflow | head -15

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for all pods to initialize"
echo "2. Run: ./port_forward_v2.sh"
echo "3. Access UI at: http://localhost:8080"
echo ""
echo "To check status: kubectl get pods -n kubeflow"
echo -e "${GREEN}================================================${NC}"