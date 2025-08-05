#!/bin/bash

# Kubeflow Pipelines Upgrade Script to v2.14.0
# This script upgrades an existing KFP installation to version 2.14.0

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Kubeflow Pipelines Upgrade to v2.14.0${NC}"
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

# Step 1: Backup current state
echo -e "\n${YELLOW}Step 1: Backing up current installation...${NC}"

# Create backup directory
BACKUP_DIR="./kubeflow-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "→ Backing up current deployments..."
kubectl get deployment -n kubeflow -o yaml > "$BACKUP_DIR/deployments.yaml"
kubectl get service -n kubeflow -o yaml > "$BACKUP_DIR/services.yaml"
kubectl get configmap -n kubeflow -o yaml > "$BACKUP_DIR/configmaps.yaml"
kubectl get secret -n kubeflow -o yaml > "$BACKUP_DIR/secrets.yaml"

echo -e "${GREEN}✓ Backup created in $BACKUP_DIR${NC}"

# Step 2: Check current version
echo -e "\n${YELLOW}Step 2: Checking current installation...${NC}"
CURRENT_VERSION=$(kubectl get deployment ml-pipeline -n kubeflow -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
echo "Current ML Pipeline version: $CURRENT_VERSION"

# Step 3: Scale down deployments
echo -e "\n${YELLOW}Step 3: Scaling down deployments...${NC}"
echo "→ Scaling down ml-pipeline deployments..."
kubectl scale deployment -n kubeflow \
    ml-pipeline \
    ml-pipeline-ui \
    ml-pipeline-persistenceagent \
    ml-pipeline-scheduledworkflow \
    ml-pipeline-viewer-crd \
    ml-pipeline-visualizationserver \
    metadata-grpc-deployment \
    metadata-writer \
    cache-server \
    --replicas=0 2>/dev/null || true

echo "→ Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=ml-pipeline -n kubeflow --timeout=60s 2>/dev/null || true

echo -e "${GREEN}✓ Deployments scaled down${NC}"

# Step 4: Apply KFP v2.14.0
echo -e "\n${YELLOW}Step 4: Installing Kubeflow Pipelines v2.14.0...${NC}"
export PIPELINE_VERSION=2.14.0

# Apply the new version
echo "→ Applying KFP v$PIPELINE_VERSION manifests..."

# Apply CRDs first
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION" --server-side

# Wait for CRDs to be established
echo "→ Waiting for CRDs to be ready..."
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io 2>/dev/null || true

# Apply base components
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION" --server-side

echo -e "${GREEN}✓ KFP v$PIPELINE_VERSION manifests applied${NC}"

# Step 5: Update configurations for SQLite
echo -e "\n${YELLOW}Step 5: Updating configurations...${NC}"

# Wait for deployments to be created
sleep 10

# Update ml-pipeline for SQLite
echo "→ Configuring ml-pipeline for SQLite..."
kubectl patch deployment ml-pipeline -n kubeflow --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env", "value": [
    {"name": "DBCONFIG_DRIVER", "value": "sqlite3"},
    {"name": "DBCONFIG_DATABASE", "value": "/var/mlpipeline/mlpipeline.db"},
    {"name": "DBCONFIG_USER", "value": ""},
    {"name": "DBCONFIG_PASSWORD", "value": ""},
    {"name": "OBJECTSTORECONFIG_BUCKETNAME", "value": "mlpipeline"},
    {"name": "OBJECTSTORECONFIG_HOST", "value": "minio-service.kubeflow"},
    {"name": "OBJECTSTORECONFIG_PORT", "value": "9000"},
    {"name": "OBJECTSTORECONFIG_SECURE", "value": "false"},
    {"name": "OBJECTSTORECONFIG_ACCESSKEY", "value": "minio"},
    {"name": "OBJECTSTORECONFIG_SECRETACCESSKEY", "value": "minio123"},
    {"name": "POD_NAMESPACE", "valueFrom": {"fieldRef": {"fieldPath": "metadata.namespace"}}}
  ]}
]' || echo "  ml-pipeline patch skipped"

# Update metadata service configmap
echo "→ Updating metadata configmap..."
kubectl apply -f - <<EOF
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
  DBCONFIG_DRIVER: "sqlite"
  DBCONFIG_DATABASE: "/tmp/metadata.db"
  connectionConfig.proto: |
    chunk_size_bytes: 1048576
    type_config {
      state_update_rule: SYNC_LAST_WRITE_WINS
    }
EOF

# Update workflow controller configmap
echo "→ Updating workflow controller configuration..."
kubectl apply -f - <<EOF
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
        cpu: 0.01
  workflowDefaults: |
    spec:
      serviceAccountName: argo
      archiveLogs: true
EOF

echo -e "${GREEN}✓ Configurations updated${NC}"

# Step 6: Scale up deployments
echo -e "\n${YELLOW}Step 6: Scaling up deployments...${NC}"
echo "→ Scaling up ml-pipeline deployments..."
kubectl scale deployment -n kubeflow \
    ml-pipeline \
    ml-pipeline-ui \
    ml-pipeline-persistenceagent \
    ml-pipeline-scheduledworkflow \
    ml-pipeline-viewer-crd \
    ml-pipeline-visualizationserver \
    metadata-grpc-deployment \
    metadata-writer \
    cache-server \
    --replicas=1

# Step 7: Verify deployment
echo -e "\n${YELLOW}Step 7: Verifying deployment...${NC}"
echo "→ Waiting for deployments to be ready..."

for deployment in ml-pipeline ml-pipeline-ui metadata-grpc-deployment; do
    echo -n "  Waiting for $deployment..."
    kubectl rollout status deployment/$deployment -n kubeflow --timeout=300s || echo " timeout"
done

# Check versions
echo -e "\n${YELLOW}Checking upgraded versions...${NC}"
NEW_VERSION=$(kubectl get deployment ml-pipeline -n kubeflow -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
echo "New ML Pipeline version: $NEW_VERSION"

# Final status
echo -e "\n${YELLOW}Final status check...${NC}"
kubectl get pods -n kubeflow | grep -E "(ml-pipeline|metadata|cache)" | head -20

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}Upgrade Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Kubeflow Pipelines has been upgraded to v$PIPELINE_VERSION"
echo ""
echo "To verify the upgrade:"
echo "1. Run: kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80"
echo "2. Open: http://localhost:8080"
echo "3. Check the version in the UI footer"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "If you encounter issues, you can restore from backup:"
echo "  kubectl apply -f $BACKUP_DIR/*.yaml"
echo -e "${GREEN}================================================${NC}"