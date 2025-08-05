#!/bin/bash

# Install Kubeflow Pipelines Standalone
# This is the simplest way to get started with Kubeflow Pipelines

set -e

echo "Installing Kubeflow Pipelines (Standalone) on Kubernetes..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Not connected to Kubernetes cluster."
    exit 1
fi

# Install Kubeflow Pipelines using the dev quickstart method
echo "Deploying Kubeflow Pipelines..."

# Option 1: Using the latest quickstart manifest
kubectl apply -k github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=master

# Wait for deployments
echo "Waiting for Kubeflow Pipelines to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/ml-pipeline -n kubeflow
kubectl wait --for=condition=available --timeout=600s deployment/ml-pipeline-ui -n kubeflow

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
echo "Kubeflow Pipelines installation completed!"
echo "========================================="
echo ""
echo "To access the Kubeflow Pipelines UI:"
echo "1. Run: ./port_forward_kfp.sh"
echo "2. Open browser at: http://localhost:8080"
echo ""

# Show status
echo "Current status:"
kubectl get pods -n kubeflow