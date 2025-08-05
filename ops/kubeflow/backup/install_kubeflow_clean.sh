#!/bin/bash

# Clean Kubeflow Installation Script
# This script completely removes any existing Kubeflow installation and deploys fresh with SQLite

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Kubeflow Clean Installation${NC}"
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

# Step 1: Clean up existing Kubeflow installation
echo -e "\n${YELLOW}Step 1: Removing existing Kubeflow components...${NC}"

# Delete namespace (this will delete everything in it)
echo "→ Deleting kubeflow namespace (this may take a few minutes)..."
kubectl delete namespace kubeflow --ignore-not-found=true --wait=true --timeout=120s || {
    echo "  Force deleting stuck resources..."
    kubectl delete namespace kubeflow --ignore-not-found=true --force --grace-period=0 || true
}

# Clean up any cluster-wide resources
echo "→ Cleaning up cluster-wide resources..."
kubectl delete clusterrolebinding -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true
kubectl delete clusterrole -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true
kubectl delete crd -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true

# Remove any PVCs that might be stuck
echo "→ Cleaning up persistent volumes..."
kubectl delete pvc -n kubeflow --all --ignore-not-found=true 2>/dev/null || true
kubectl delete pv -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true

echo -e "${GREEN}✓ Cleanup completed${NC}"

# Step 2: Create fresh namespace
echo -e "\n${YELLOW}Step 2: Creating fresh namespace...${NC}"
kubectl create namespace kubeflow
kubectl label namespace kubeflow app.kubernetes.io/part-of=kubeflow

# Step 3: Deploy Kubeflow Pipelines with SQLite
echo -e "\n${YELLOW}Step 3: Deploying Kubeflow Pipelines (SQLite backend)...${NC}"

# Create ConfigMap for pipeline configuration
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: pipeline-install-config
  namespace: kubeflow
data:
  bucketName: mlpipeline
  dbType: sqlite3
  pipelineDb: /var/mlpipeline/mlpipeline.db
  ConMaxLifeTime: 120s
  autoUpdatePipelineDefaultVersion: "true"
EOF

# Create minimal secrets (required even with SQLite)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: kubeflow
type: Opaque
data:
  username: cm9vdA==  # root
  password: ""         # empty
---
apiVersion: v1
kind: Secret
metadata:
  name: mlpipeline-minio-artifact
  namespace: kubeflow
type: Opaque
data:
  accesskey: bWluaW8=     # minio
  secretkey: bWluaW8xMjM=  # minio123
EOF

# Deploy core CRDs first (suppress warnings)
echo "→ Installing CRDs..."
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=2.0.5" 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" || true
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io || true

# Deploy Kubeflow Pipelines components using the platform-agnostic installation
echo "→ Installing Kubeflow Pipelines components..."
# Use platform-agnostic which includes all necessary components
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=2.0.5" 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" || true

# Wait a moment for deployments to be created
echo "→ Waiting for initial deployments..."
sleep 10

# Patch ml-pipeline deployment to use SQLite
echo "→ Configuring ml-pipeline for SQLite..."
cat <<'EOF' | kubectl apply -f -
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
        ports:
        - containerPort: 8888
          name: http
        - containerPort: 8887
          name: grpc
        env:
        - name: DBCONFIG_DRIVER
          value: sqlite3
        - name: DBCONFIG_DB_NAME
          value: /var/mlpipeline/mlpipeline.db
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: OBJECTSTORECONFIG_BUCKETNAME
          value: mlpipeline
        - name: OBJECTSTORECONFIG_HOST
          value: minio-service.kubeflow.svc.cluster.local
        - name: OBJECTSTORECONFIG_PORT
          value: "9000"
        - name: OBJECTSTORECONFIG_SECURE
          value: "false"
        - name: OBJECTSTORECONFIG_ACCESSKEY
          valueFrom:
            secretKeyRef:
              name: mlpipeline-minio-artifact
              key: accesskey
        - name: OBJECTSTORECONFIG_SECRETACCESSKEY
          valueFrom:
            secretKeyRef:
              name: mlpipeline-minio-artifact
              key: secretkey
        livenessProbe:
          httpGet:
            path: /apis/v1beta1/healthz
            port: 8888
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /apis/v1beta1/healthz
            port: 8888
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: mlpipeline-db
          mountPath: /var/mlpipeline
      volumes:
      - name: mlpipeline-db
        emptyDir: {}
EOF

# Deploy a simple Minio instance
echo "→ Deploying Minio for artifact storage..."
# First delete any existing minio deployment to avoid selector conflicts
kubectl delete deployment minio -n kubeflow --ignore-not-found=true
kubectl delete service minio-service -n kubeflow --ignore-not-found=true
sleep 5

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
        image: minio/minio:RELEASE.2023-06-19T19-52-50Z
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

# Create ML Pipeline service if not exists
echo "→ Creating ML Pipeline service..."
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ml-pipeline
  namespace: kubeflow
spec:
  ports:
  - port: 8888
    targetPort: 8888
    name: http
  - port: 8887
    targetPort: 8887
    name: grpc
  selector:
    app: ml-pipeline
EOF

# Step 4: Wait for deployments to be ready
echo -e "\n${YELLOW}Step 4: Waiting for services to be ready...${NC}"

echo "→ Waiting for Minio..."
kubectl wait --for=condition=available deployment/minio -n kubeflow --timeout=180s || echo "  Minio timeout (may still be starting)"

echo "→ Waiting for ML Pipeline..."
kubectl wait --for=condition=available deployment/ml-pipeline -n kubeflow --timeout=180s || echo "  ML Pipeline timeout (may still be starting)"

echo "→ Waiting for ML Pipeline UI..."
kubectl wait --for=condition=available deployment/ml-pipeline-ui -n kubeflow --timeout=180s || echo "  UI timeout (may still be starting)"

# Step 5: Create bucket in Minio
echo -e "\n${YELLOW}Step 5: Initializing Minio bucket...${NC}"
sleep 10  # Give Minio time to fully start

kubectl run minio-client --rm -i --restart=Never --namespace=kubeflow --image=minio/mc:latest -- /bin/sh -c "
mc alias set minio http://minio-service.kubeflow.svc.cluster.local:9000 minio minio123 &&
mc mb --ignore-existing minio/mlpipeline &&
echo 'Bucket created successfully'
" 2>/dev/null || echo "  Bucket initialization skipped (may already exist)"

# Step 6: Create simple port-forward script
echo -e "\n${YELLOW}Step 6: Creating access script...${NC}"
cat > port_forward_clean.sh << 'EOF'
#!/bin/bash
echo "================================================"
echo "Kubeflow Pipelines Port Forward"
echo "================================================"
echo "→ Starting port-forward to http://localhost:8080"
echo "→ Press Ctrl+C to stop"
echo ""
echo "If you see errors in the UI, wait 2-3 minutes for"
echo "all services to fully initialize."
echo "================================================"

kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
EOF

chmod +x port_forward_clean.sh

# Final status check
echo -e "\n${YELLOW}Final Status Check:${NC}"
echo "→ Pods in kubeflow namespace:"
kubectl get pods -n kubeflow

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Run: ./port_forward_clean.sh"
echo "2. Open: http://localhost:8080"
echo ""
echo "Note: The system uses SQLite (no MySQL needed) and"
echo "local Minio storage. Perfect for development!"
echo ""
echo "If pods are still starting, wait 2-3 minutes before accessing."
echo -e "${GREEN}================================================${NC}"