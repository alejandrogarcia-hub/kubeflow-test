#!/bin/bash

# Minimal Kubeflow installation for ML Pipeline development
# Installs: Pipelines, Central Dashboard, Notebooks, KServe

set -e

echo "Installing minimal Kubeflow setup on Docker Desktop Kubernetes..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Not connected to Kubernetes cluster."
    exit 1
fi

# Create kubeflow namespace
echo "Creating kubeflow namespace..."
kubectl create namespace kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Install Kubeflow Pipelines (standalone)
echo "Installing Kubeflow Pipelines..."
export PIPELINE_VERSION=2.3.0
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-pns?ref=$PIPELINE_VERSION"

# Wait for pipelines to be ready
echo "Waiting for Kubeflow Pipelines to be ready..."
kubectl wait --for=condition=ready pod -l app=ml-pipeline -n kubeflow --timeout=300s

# Install KServe
echo "Installing KServe..."
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml
kubectl wait --for=condition=ready pod -l control-plane=kserve-controller-manager -n kserve --timeout=180s

# Create access script
cat > access_kubeflow_pipelines.sh << 'EOF'
#!/bin/bash
echo "Starting port-forward to Kubeflow Pipelines UI..."
echo "Access Pipelines UI at: http://localhost:8080"
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
EOF

chmod +x access_kubeflow_pipelines.sh

echo ""
echo "========================================="
echo "Minimal Kubeflow installation completed!"
echo "========================================="
echo ""
echo "Installed components:"
echo "- Kubeflow Pipelines"
echo "- KServe (for model serving)"
echo ""
echo "To access Kubeflow Pipelines UI:"
echo "1. Run: ./access_kubeflow_pipelines.sh"
echo "2. Open browser at: http://localhost:8080"
echo ""

# Check installation status
echo "Checking installation status..."
kubectl get pods -n kubeflow
echo ""
kubectl get pods -n kserve