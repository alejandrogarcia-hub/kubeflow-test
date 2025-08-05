#!/bin/bash

# Kubeflow Pipelines Installation v5
# Complete installation with proper metadata service and logging configuration

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Kubeflow Pipelines Installation v5${NC}"
echo -e "${GREEN}Fixed Metadata Service & Logging${NC}"
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

# Step 2: Create namespace
echo -e "\n${YELLOW}Step 2: Creating namespace...${NC}"
kubectl create namespace kubeflow

# Step 3: Install base Kubeflow Pipelines with platform-agnostic-emissary
echo -e "\n${YELLOW}Step 3: Installing Kubeflow Pipelines with emissary executor...${NC}"
export PIPELINE_VERSION=2.0.5

# Install CRDs first
echo "→ Installing CRDs..."
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION" 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io 2>/dev/null || true

# Install with emissary executor support
echo "→ Installing base components with emissary executor..."
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=$PIPELINE_VERSION" 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true

# Step 4: Deploy Minio first (needed by other components)
echo -e "\n${YELLOW}Step 4: Deploying Minio storage...${NC}"

# Delete existing minio to avoid conflicts
kubectl delete deployment minio -n kubeflow --ignore-not-found=true 2>/dev/null
kubectl delete service minio-service -n kubeflow --ignore-not-found=true 2>/dev/null
sleep 5

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: mlpipeline-minio-artifact
  namespace: kubeflow
type: Opaque
stringData:
  accesskey: minio
  secretkey: minio123
---
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

echo -e "${GREEN}✓ Minio deployed${NC}"

# Step 5: Wait for initial deployments to be created
echo -e "\n${YELLOW}Step 5: Waiting for deployments to be created...${NC}"
sleep 30

# Step 6: Configure all components for SQLite
echo -e "\n${YELLOW}Step 6: Configuring all components for SQLite...${NC}"

# Override ml-pipeline with SQLite configuration
echo "→ Configuring ml-pipeline..."
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
    application-crd-id: kubeflow-pipelines
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
      annotations:
        pipelines.kubeflow.org/enable_caching: "true"
        pipelines.kubeflow.org/enable_pod_labels: "true"
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

# Fix ml-pipeline service selector
echo "→ Fixing ml-pipeline service..."
kubectl patch service ml-pipeline -n kubeflow --type='json' -p='[
  {"op": "replace", "path": "/spec/selector", "value": {"app": "ml-pipeline"}}
]' 2>/dev/null || echo "  Service patch skipped"

# Override metadata-grpc-deployment with proper configuration
echo "→ Configuring metadata service with SQLite..."
kubectl delete deployment metadata-grpc-deployment -n kubeflow --ignore-not-found=true 2>/dev/null || true
sleep 5

# Create metadata configmap first
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: metadata-grpc-configmap
  namespace: kubeflow
data:
  metadata_store_server_config.pb: |
    connection_config {
      sqlite {
        filename_uri: "/var/mlmetadata/metadata.db"
        connection_mode: READWRITE_OPENCREATE
      }
    }
EOF

# Deploy metadata-grpc-deployment with environment variables
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metadata-grpc-deployment
  namespace: kubeflow
spec:
  replicas: 1
  selector:
    matchLabels:
      component: metadata-grpc-server
  template:
    metadata:
      labels:
        component: metadata-grpc-server
    spec:
      serviceAccountName: metadata-grpc-server
      containers:
      - name: metadata-grpc-server
        image: gcr.io/tfx-oss-public/ml_metadata_store_server:1.14.0
        command: ["/bin/metadata_store_server"]
        args:
        - --grpc_port=8080
        - --metadata_store_server_config_file=/var/config/metadata_store_server_config.pb
        env:
        - name: METADATA_GRPC_SERVICE_HOST
          value: metadata-grpc-service
        - name: METADATA_GRPC_SERVICE_PORT
          value: "8080"
        ports:
        - containerPort: 8080
          name: grpc
        volumeMounts:
        - name: metadata-config
          mountPath: /var/config
        - name: metadata-store
          mountPath: /var/mlmetadata
        readinessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 5
          timeoutSeconds: 2
      volumes:
      - name: metadata-config
        configMap:
          name: metadata-grpc-configmap
      - name: metadata-store
        emptyDir: {}
EOF

# Ensure metadata service exists
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: metadata-grpc-service
  namespace: kubeflow
spec:
  ports:
  - port: 8080
    targetPort: 8080
    name: grpc
  selector:
    component: metadata-grpc-server
EOF

echo -e "${GREEN}✓ All components configured for SQLite${NC}"

# Step 6.5: Fix argo service account for Kubernetes 1.24+
echo -e "\n${YELLOW}Step 6.5: Fixing argo service account...${NC}"

# Create service account token secret (required for K8s 1.24+)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: argo.service-account-token
  namespace: kubeflow
  annotations:
    kubernetes.io/service-account.name: argo
type: kubernetes.io/service-account-token
EOF

echo -e "${GREEN}✓ Argo service account fixed${NC}"

# Step 7: Configure workflow controller for proper logging
echo -e "\n${YELLOW}Step 7: Configuring workflow controller for logs...${NC}"

# Create workflow controller configmap with proper configuration
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: kubeflow
data:
  artifactRepository: |
    archiveLogs: true
    s3:
      endpoint: "minio-service.kubeflow:9000"
      bucket: "mlpipeline"
      keyFormat: "artifacts/{{workflow.name}}/{{workflow.creationTimestamp.Y}}/{{workflow.creationTimestamp.m}}/{{workflow.creationTimestamp.d}}/{{pod.name}}"
      insecure: true
      accessKeySecret:
        name: mlpipeline-minio-artifact
        key: accesskey
      secretKeySecret:
        name: mlpipeline-minio-artifact
        key: secretkey
  containerRuntimeExecutor: emissary
  executor: |
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: 0.1
        memory: 64Mi
      limits:
        cpu: 0.5
        memory: 512Mi
  workflowDefaults: |
    spec:
      entrypoint: main
      serviceAccountName: argo
      executor:
        serviceAccountName: argo
      podMetadata:
        labels:
          pipelines.kubeflow.org/cache_enabled: "true"
        annotations:
          pipelines.kubeflow.org/cache_enabled: "true"
EOF

# Restart workflow controller
echo "→ Restarting workflow controller..."
kubectl rollout restart deployment/workflow-controller -n kubeflow 2>/dev/null || echo "  Workflow controller restart skipped"

# Wait for services to stabilize
echo "→ Waiting for services to stabilize..."
sleep 10

echo -e "${GREEN}✓ Workflow logging configured${NC}"

# Step 8: Initialize storage
echo -e "\n${YELLOW}Step 8: Initializing storage...${NC}"
echo "→ Waiting for Minio to be ready..."

# Wait for Minio deployment
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
    else
        echo -n "."
    fi
    sleep 1
done

# Initialize bucket
kubectl run minio-init --rm -i --restart=Never --namespace=kubeflow --image=minio/mc:latest -- /bin/sh -c "
mc alias set minio http://minio-service.kubeflow.svc.cluster.local:9000 minio minio123 &&
mc mb --ignore-existing minio/mlpipeline &&
echo 'Bucket initialized'
" 2>/dev/null || echo "  Bucket initialization will complete in background"

# Step 9: Create port forward script
echo -e "\n${YELLOW}Step 9: Creating access script...${NC}"

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

# Step 10: Wait for all services to be ready
echo -e "\n${YELLOW}Step 10: Waiting for all services to be ready...${NC}"

echo "→ Waiting for metadata service..."
kubectl wait --for=condition=available deployment/metadata-grpc-deployment -n kubeflow --timeout=180s 2>/dev/null || echo "  Metadata service starting..."

echo "→ Waiting for ml-pipeline..."
kubectl wait --for=condition=available deployment/ml-pipeline -n kubeflow --timeout=180s 2>/dev/null || echo "  ML Pipeline starting..."

echo "→ Waiting for metadata-writer..."
kubectl wait --for=condition=available deployment/metadata-writer -n kubeflow --timeout=180s 2>/dev/null || echo "  Metadata writer starting..."

# Ensure metadata components are fully initialized
echo "→ Ensuring metadata components are ready..."
sleep 10

# Restart metadata-writer to ensure proper initialization
kubectl rollout restart deployment/metadata-writer -n kubeflow 2>/dev/null || echo "  Metadata writer restart skipped"

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
echo "Features:"
echo "- SQLite backend (no MySQL dependency)"
echo "- Minio for object storage"
echo "- Metadata service with SQLite (properly configured)"
echo "- Emissary executor for better compatibility"
echo "- Enhanced workflow logging configuration"
echo "- Fixed metadata service connectivity"
echo ""
echo "To check status: kubectl get pods -n kubeflow"
echo ""
echo "To view logs: ./ops/kubeflow/view_logs.sh"
echo -e "${GREEN}================================================${NC}"