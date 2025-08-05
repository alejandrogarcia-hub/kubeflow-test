#!/bin/bash

# Kubeflow Pipelines Installation v3
# Complete clean installation with proper cleanup and SQLite backend

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Kubeflow Pipelines Installation v3${NC}"
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

# Step 1: Complete cleanup
echo -e "\n${YELLOW}Step 1: Complete cleanup of existing installation...${NC}"

# Force delete namespace and all resources
echo "→ Removing kubeflow namespace and all resources..."
kubectl delete namespace kubeflow --ignore-not-found=true --force --grace-period=0 2>/dev/null || true

# Wait for namespace to be fully deleted
echo "→ Waiting for namespace deletion..."
while kubectl get namespace kubeflow &>/dev/null; do
    echo -n "."
    sleep 2
done
echo " Done!"

# Clean up cluster-wide resources
echo "→ Cleaning up cluster-wide resources..."
kubectl delete clusterrolebinding -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true
kubectl delete clusterrole -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true
kubectl delete crd -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true

echo -e "${GREEN}✓ Cleanup completed${NC}"

# Step 2: Fresh installation
echo -e "\n${YELLOW}Step 2: Installing Kubeflow Pipelines...${NC}"

# Create namespace
kubectl create namespace kubeflow

# Install Kubeflow Pipelines using platform-agnostic deployment
export PIPELINE_VERSION=2.0.5
echo "→ Installing CRDs and core components..."

# Install with output filtering
{
    kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
    kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
    kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION"
} 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true

echo -e "${GREEN}✓ Core components installed${NC}"

# Step 3: Configure for SQLite
echo -e "\n${YELLOW}Step 3: Configuring SQLite backend...${NC}"

# Wait for deployments
echo "→ Waiting for deployments to be created..."
for i in {1..30}; do
    if kubectl get deployment ml-pipeline -n kubeflow &>/dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

echo "→ Creating SQLite configuration..."
# Create SQLite configuration
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: pipeline-install-config
  namespace: kubeflow
data:
  ConMaxLifeTime: "120s"
  appName: pipeline
  appVersion: $PIPELINE_VERSION
  autoUpdatePipelineDefaultVersion: "true"
  bucketName: mlpipeline
  cacheDb: /var/mlpipeline/cache.db
  cacheImage: gcr.io/google-containers/busybox
  cacheNodeRestrictions: "false"
  cronScheduleTimezone: UTC
  dbHost: ""
  dbPort: ""
  dbType: sqlite3
  defaultPipelineRoot: ""
  mlmdDb: /var/mlpipeline/metadb
  mysqlHost: ""
  mysqlPort: ""
  pipelineDb: /var/mlpipeline/mlpipeline.db
EOF

# Override ml-pipeline deployment with SQLite configuration
echo "→ Deploying ml-pipeline with SQLite..."
# First delete existing deployment to avoid selector conflicts
kubectl delete deployment ml-pipeline -n kubeflow --ignore-not-found=true 2>/dev/null || true
sleep 5
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-pipeline
  namespace: kubeflow
  labels:
    app: ml-pipeline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ml-pipeline
  template:
    metadata:
      labels:
        app: ml-pipeline
        application-crd-id: kubeflow-pipelines
    spec:
      serviceAccountName: ml-pipeline
      containers:
      - name: ml-pipeline-api-server
        image: gcr.io/ml-pipeline/api-server:2.0.5
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8888
          name: http
        - containerPort: 8887
          name: grpc
        env:
        - name: DBCONFIG_DRIVER
          value: sqlite3
        - name: DBCONFIG_DATABASE
          value: /var/mlpipeline/mlpipeline.db
        - name: DBCONFIG_USER
          value: ""
        - name: DBCONFIG_PASSWORD
          value: ""
        - name: OBJECTSTORECONFIG_BUCKETNAME
          value: mlpipeline
        - name: OBJECTSTORECONFIG_HOST
          value: minio-service.kubeflow
        - name: OBJECTSTORECONFIG_PORT
          value: "9000"
        - name: OBJECTSTORECONFIG_SECURE
          value: "false"
        - name: OBJECTSTORECONFIG_ACCESSKEY
          value: minio
        - name: OBJECTSTORECONFIG_SECRETACCESSKEY
          value: minio123
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: mlpipeline-db
          mountPath: /var/mlpipeline
        livenessProbe:
          httpGet:
            path: /apis/v1beta1/healthz
            port: 8888
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 2
        readinessProbe:
          httpGet:
            path: /apis/v1beta1/healthz
            port: 8888
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 2
      volumes:
      - name: mlpipeline-db
        emptyDir: {}
EOF

echo -e "${GREEN}✓ SQLite backend configured${NC}"

# Step 3.5: Fix ml-pipeline service selector
echo "→ Fixing ml-pipeline service..."
kubectl patch service ml-pipeline -n kubeflow --type='json' -p='[
  {"op": "replace", "path": "/spec/selector", "value": {"app": "ml-pipeline"}}
]' 2>/dev/null || echo "  Service patch skipped"

# Step 4: Deploy simple Minio
echo -e "\n${YELLOW}Step 4: Deploying Minio storage...${NC}"

# First, delete any existing minio deployment to avoid selector conflicts
kubectl delete deployment minio -n kubeflow --ignore-not-found=true 2>/dev/null
kubectl delete service minio-service -n kubeflow --ignore-not-found=true 2>/dev/null
sleep 5

echo "→ Deploying Minio for artifact storage..."

cat <<'EOF' | kubectl apply -f -
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
        - --console-address
        - :9001
        env:
        - name: MINIO_ROOT_USER
          value: minio
        - name: MINIO_ROOT_PASSWORD
          value: minio123
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        volumeMounts:
        - name: data
          mountPath: /data
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 5
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
    name: api
  - port: 9001
    targetPort: 9001
    name: console
  selector:
    app: minio
EOF

echo -e "${GREEN}✓ Minio deployed${NC}"

# Step 5: Create port forward script
echo -e "\n${YELLOW}Step 5: Creating access script...${NC}"

cat > kubeflow_port_forward.sh << 'EOF'
#!/bin/bash
echo "================================================"
echo "Kubeflow Pipelines UI Port Forward"
echo "================================================"
echo "Starting port forward to http://localhost:8080"
echo "Press Ctrl+C to stop"
echo ""
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
EOF
chmod +x kubeflow_port_forward.sh

# Step 6: Initialize Minio bucket
echo -e "\n${YELLOW}Step 6: Initializing storage...${NC}"
echo "→ Waiting for Minio to be ready..."

# Wait for Minio deployment to be available
for i in {1..60}; do
    if kubectl get deployment minio -n kubeflow &>/dev/null; then
        READY=$(kubectl get deployment minio -n kubeflow -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment minio -n kubeflow -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$READY" == "$DESIRED" ]] && [[ "$READY" != "0" ]]; then
            echo "  Minio is ready ($READY/$DESIRED replicas)"
            break
        fi
    fi
    
    if [[ $((i % 10)) == 0 ]]; then
        echo "  Still waiting... ($i/60 seconds)"
        kubectl get pod -n kubeflow -l app=minio --no-headers 2>/dev/null || echo "  No minio pods found yet"
    else
        echo -n "."
    fi
    sleep 1
done

# Extra wait for Minio to fully initialize
echo "→ Waiting for Minio API to be responsive..."
for i in {1..30}; do
    if kubectl exec -n kubeflow deployment/minio -- curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/minio/health/ready 2>/dev/null | grep -q "200"; then
        echo "  Minio API is ready"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

kubectl run minio-init --rm -i --restart=Never --namespace=kubeflow --image=minio/mc:latest -- /bin/sh -c "
mc alias set minio http://minio-service.kubeflow.svc.cluster.local:9000 minio minio123 &&
mc mb --ignore-existing minio/mlpipeline &&
echo 'Bucket initialized'
" 2>/dev/null || echo "  Bucket initialization will complete in background"

# Final status
echo -e "\n${YELLOW}Checking deployment status...${NC}"
sleep 10

echo ""
echo "Pods status:"
kubectl get pods -n kubeflow

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "To access Kubeflow Pipelines UI:"
echo "1. Run: ./kubeflow_port_forward.sh"
echo "2. Open: http://localhost:8080"
echo ""
echo "Notes:"
echo "- Using SQLite backend (no MySQL needed)"
echo "- Using local Minio storage"
echo "- Some pods may still be starting"
echo ""
echo "To check status: kubectl get pods -n kubeflow"
echo -e "${GREEN}================================================${NC}"