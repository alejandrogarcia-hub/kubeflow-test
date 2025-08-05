#!/bin/bash

# Install Kubeflow Pipelines using platform-agnostic deployment
# Based on community recommendations for stable installation

set -e

echo "Installing Kubeflow Pipelines on Kubernetes..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Not connected to Kubernetes cluster."
    exit 1
fi

# Create namespace if it doesn't exist
echo "Creating kubeflow namespace..."
kubectl create namespace kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Set pipeline version
export PIPELINE_VERSION=2.0.5

echo "Using Kubeflow Pipelines version: $PIPELINE_VERSION"

# Install Kubeflow Pipelines using platform-agnostic deployment
echo "Deploying Kubeflow Pipelines (platform-agnostic)..."
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION"

# Wait for critical deployments (don't wait for all pods as some might have issues)
echo "Waiting for core services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/ml-pipeline-ui -n kubeflow || true
kubectl wait --for=condition=available --timeout=300s deployment/ml-pipeline -n kubeflow || true

# Create port-forward script
cat > port_forward_kfp.sh << 'EOF'
#!/bin/bash
echo "Starting port-forward to Kubeflow Pipelines UI..."
echo "Access the UI at: http://localhost:8080"
echo "Press Ctrl+C to stop"
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
EOF

chmod +x port_forward_kfp.sh

echo ""
echo "========================================="
echo "Kubeflow Pipelines installation initiated!"
echo "========================================="
echo ""
echo "Note: Some pods might show errors but the UI should still work."
echo ""
echo "To access the Kubeflow Pipelines UI:"
echo "1. Run: ./port_forward_kfp.sh"
echo "2. Open browser at: http://localhost:8080"
echo ""

# Show status
echo "Current pod status:"
kubectl get pods -n kubeflow | head -20
echo ""
echo "To see all pods: kubectl get pods -n kubeflow"