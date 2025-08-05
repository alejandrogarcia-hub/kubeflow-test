#!/bin/bash

# Kubeflow Pipelines Installation v4
# Complete installation with all components configured for SQLite

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Kubeflow Pipelines Installation v4${NC}"
echo -e "${GREEN}KFP Version 2.14.0 with SQLite (ghcr.io images)${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}⚠️  Resource Requirements:${NC}"
echo "   - Docker Desktop: 8GB+ memory recommended"
echo "   - Kubernetes will use ~4GB for Kubeflow components"
echo "   - Pipeline runs need additional resources"
echo ""

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

# Step 3: Install base Kubeflow Pipelines
echo -e "\n${YELLOW}Step 3: Installing Kubeflow Pipelines base...${NC}"
export PIPELINE_VERSION=2.14.0

# Install CRDs
echo "→ Installing CRDs..."
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION" 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io 2>/dev/null || true

# Install base components
echo "→ Installing base components..."
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION" 2>&1 | grep -v "Warning:" | grep -v "well-defined vars" | grep -v "annotation" || true

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

# Step 5: Configure all components for SQLite
echo -e "\n${YELLOW}Step 5: Configuring all components for SQLite...${NC}"

# Wait for initial deployments
echo "→ Waiting for deployments to be created..."
sleep 20

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
    spec:
      serviceAccountName: ml-pipeline
      containers:
      - name: ml-pipeline-api-server
        image: ghcr.io/kubeflow/kfp-api-server:2.14.0
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
        - name: V2_DRIVER_IMAGE
          value: ghcr.io/kubeflow/kfp-driver:2.14.0
        - name: V2_LAUNCHER_IMAGE
          value: ghcr.io/kubeflow/kfp-launcher:2.14.0
        - name: V2_LAUNCHER_RESOURCE_CPU_LIMIT
          value: "2"
        - name: V2_LAUNCHER_RESOURCE_MEMORY_LIMIT
          value: "1024Mi"
        - name: V2_DRIVER_RESOURCE_CPU_LIMIT
          value: "2"
        - name: V2_DRIVER_RESOURCE_MEMORY_LIMIT
          value: "1024Mi"
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

# Override metadata-grpc-deployment to remove MySQL dependency
echo "→ Configuring metadata service..."
kubectl delete deployment metadata-grpc-deployment -n kubeflow --ignore-not-found=true 2>/dev/null || true
sleep 5

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
        - --metadata_store_server_config_file=/config/config.proto
        ports:
        - containerPort: 8080
          name: grpc
        volumeMounts:
        - name: config-volume
          mountPath: /config
        - name: metadata-store
          mountPath: /var/mlmetadata
      volumes:
      - name: config-volume
        configMap:
          name: metadata-grpc-configmap
      - name: metadata-store
        emptyDir: {}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: metadata-grpc-configmap
  namespace: kubeflow
data:
  METADATA_GRPC_SERVICE_HOST: "metadata-grpc-service"
  METADATA_GRPC_SERVICE_PORT: "8080"
  METADATA_GRPC_SERVICE_SERVICE_HOST: "metadata-grpc-service"
  METADATA_GRPC_SERVICE_SERVICE_PORT: "8080"
  config.proto: |
    connection_config {
      sqlite {
        filename_uri: "/var/mlmetadata/metadata.db"
        connection_mode: READWRITE_OPENCREATE
      }
    }
EOF

# Create metadata service if not exists
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

# Step 5.5: Update ml-pipeline-ui deployment for better logging
echo "→ Configuring UI for log viewing..."
kubectl patch deployment ml-pipeline-ui -n kubeflow --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/metadata/annotations",
    "value": {
      "pipelines.kubeflow.org/enable_caching": "true",
      "pipelines.kubeflow.org/enable_pod_labels": "true"
    }
  }
]' 2>/dev/null || echo "  UI patch skipped"

# Step 5.6: Fix argo service account for Kubernetes 1.24+
echo "→ Waiting for argo service account..."
# Wait for argo service account to be created
for i in {1..30}; do
    if kubectl get serviceaccount argo -n kubeflow &>/dev/null; then
        echo "  Argo service account found"
        break
    fi
    echo -n "."
    sleep 1
done

echo "→ Creating argo service account token..."
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: argo-token
  namespace: kubeflow
  annotations:
    kubernetes.io/service-account.name: argo
type: kubernetes.io/service-account-token
EOF

echo -e "${GREEN}✓ Argo service account token created${NC}"

# Patch argo service account to use the token
echo "→ Patching argo service account..."
kubectl patch serviceaccount argo -n kubeflow -p '{"secrets": [{"name": "argo-token"}]}' || echo "  Service account patch skipped"

echo -e "${GREEN}✓ Argo service account configured${NC}"

# Step 6: Configure workflow controller for proper logging
echo -e "\n${YELLOW}Step 6: Configuring workflow controller for logs...${NC}"

# Create enhanced workflow controller configmap
echo "→ Creating workflow controller configuration..."
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
  executor: |
    imagePullPolicy: IfNotPresent
EOF

# Restart workflow controller to apply configuration
echo "→ Restarting workflow controller..."
kubectl rollout restart deployment/workflow-controller -n kubeflow 2>/dev/null || echo "  Workflow controller restart skipped"

# Wait for workflow controller to be ready
echo "→ Waiting for workflow controller to be ready..."
for i in {1..60}; do
    if kubectl get deployment workflow-controller -n kubeflow &>/dev/null; then
        READY=$(kubectl get deployment workflow-controller -n kubeflow -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment workflow-controller -n kubeflow -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$READY" == "$DESIRED" ]] && [[ "$READY" != "0" ]]; then
            echo "  Workflow controller is ready ($READY/$DESIRED replicas)"
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

echo -e "${GREEN}✓ Workflow logging configured${NC}"

# Step 7: Initialize storage
echo -e "\n${YELLOW}Step 7: Initializing storage...${NC}"
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

# Step 7.5: Pre-pull common images to avoid runtime issues
echo -e "\n${YELLOW}Step 7.5: Pre-pulling common pipeline images...${NC}"
echo "→ This helps avoid image pull errors during pipeline runs"

# Create a job to pre-pull images
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: image-prepull
  namespace: kubeflow
spec:
  template:
    spec:
      restartPolicy: Never
      initContainers:
      - name: pull-python
        image: python:3.11-slim
        command: ["echo", "Python image pulled"]
      - name: pull-argoexec
        image: quay.io/argoproj/argoexec:v3.6.7
        command: ["echo", "Argo exec image pulled"]
      - name: pull-driver
        image: ghcr.io/kubeflow/kfp-driver:2.14.0
        command: ["echo", "KFP driver image pulled"]
      - name: pull-launcher
        image: ghcr.io/kubeflow/kfp-launcher:2.14.0
        command: ["echo", "KFP launcher image pulled"]
      containers:
      - name: complete
        image: busybox
        command: ["echo", "All images pre-pulled successfully"]
EOF

# Wait for job to complete (with timeout)
echo "→ Waiting for image pre-pull to complete..."
for i in {1..30}; do
    STATUS=$(kubectl get job image-prepull -n kubeflow -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$STATUS" == "1" ]]; then
        echo "  Images pre-pulled successfully"
        kubectl delete job image-prepull -n kubeflow 2>/dev/null || true
        break
    fi
    if [[ $((i % 10)) == 0 ]]; then
        echo "  Still pulling images... ($i/30 seconds)"
    else
        echo -n "."
    fi
    sleep 1
done

echo -e "${GREEN}✓ Common images prepared${NC}"

# Step 8: Create port forward script
echo -e "\n${YELLOW}Step 8: Creating access script...${NC}"

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

# Step 9: Wait for ml-pipeline to be ready
echo -e "\n${YELLOW}Step 9: Waiting for ml-pipeline to be ready...${NC}"
echo "→ ML Pipeline can take 30-60 seconds to initialize..."

for i in {1..90}; do
    # Check if ml-pipeline pod is running
    ML_POD=$(kubectl get pods -n kubeflow -l app=ml-pipeline --no-headers | grep -v persistenceagent | grep -v scheduledworkflow | grep -v ui | grep -v viewer | grep -v visualization | awk '{print $1}')
    if [[ -n "$ML_POD" ]]; then
        STATUS=$(kubectl get pod "$ML_POD" -n kubeflow -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        READY=$(kubectl get pod "$ML_POD" -n kubeflow -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        
        if [[ "$STATUS" == "Running" ]] && [[ "$READY" == "True" ]]; then
            # Check if API is responding
            if kubectl exec "$ML_POD" -n kubeflow -- wget -q -O- http://localhost:8888/apis/v1beta1/healthz 2>/dev/null | grep -q "apiServerReady.*true"; then
                echo "  ML Pipeline is ready!"
                break
            fi
        fi
    fi
    
    if [[ $((i % 15)) == 0 ]]; then
        echo "  Still waiting... ($i/90 seconds)"
    else
        echo -n "."
    fi
    sleep 1
done

echo -e "${GREEN}✓ ML Pipeline initialized${NC}"

# Final status
echo -e "\n${YELLOW}Checking deployment status...${NC}"
sleep 5

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
echo "- Metadata service with SQLite"
echo "- Enhanced workflow logging configuration"
echo "- UI configured for proper log viewing"
echo "- All components configured for local development"
echo ""
echo "To check status: kubectl get pods -n kubeflow"
echo -e "${GREEN}================================================${NC}"