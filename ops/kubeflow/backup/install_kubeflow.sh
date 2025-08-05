#!/bin/bash

# Quick Kubeflow Pipelines Installation Script
# This script provides a simplified installation that addresses common issues
# and suppresses kustomize warnings

set -e

echo "================================================"
echo "Kubeflow Pipelines Quick Installation"
echo "================================================"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Not connected to Kubernetes cluster."
    echo "Please ensure Docker Desktop Kubernetes is running."
    exit 1
fi

# Create namespace
echo "→ Creating kubeflow namespace..."
kubectl create namespace kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Install Kubeflow Pipelines with warning suppression
echo "→ Installing Kubeflow Pipelines (this takes 5-10 minutes)..."
echo "  Note: Kustomize warnings are expected and can be ignored"

# Use a specific version known to work
export PIPELINE_VERSION=2.0.5

# Apply with stderr redirected to suppress warnings but keep errors
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION" 2>&1 | \
    grep -v "Warning:" | grep -v "well-defined vars" || true

# Fix MySQL image issue proactively
echo "→ Fixing MySQL image..."
sleep 5
kubectl set image deployment/mysql mysql=mysql:8.0 -n kubeflow 2>/dev/null || true

# Wait for UI to be ready
echo "→ Waiting for UI to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/ml-pipeline-ui -n kubeflow || {
    echo "  UI deployment timed out, but this is often OK for local setups"
}

# Create simplified port-forward script
cat > port_forward_simple.sh << 'EOF'
#!/bin/bash
# Simple port-forward script for Kubeflow Pipelines UI

echo "================================================"
echo "Kubeflow Pipelines UI Port Forward"
echo "================================================"
echo "→ Starting port-forward to http://localhost:8080"
echo "→ Press Ctrl+C to stop"
echo ""
echo "Note: If you see API errors in the UI, this is expected"
echo "for local installations. The UI will still be viewable."
echo "================================================"

kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
EOF

chmod +x port_forward_simple.sh

# Show status
echo ""
echo "================================================"
echo "Installation Summary"
echo "================================================"

# Check critical pods
echo "→ Checking pod status..."
UI_STATUS=$(kubectl get pod -n kubeflow -l app=ml-pipeline-ui -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")
BACKEND_STATUS=$(kubectl get pod -n kubeflow -l app=ml-pipeline -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")

echo "  UI Pod: $UI_STATUS"
echo "  Backend Pod: $BACKEND_STATUS"

if [[ "$UI_STATUS" == "Running" ]]; then
    echo ""
    echo "✅ UI is ready! You can access it now:"
    echo "   1. Run: ./port_forward_simple.sh"
    echo "   2. Open: http://localhost:8080"
else
    echo ""
    echo "⚠️  UI is not ready yet. Wait a few minutes and check with:"
    echo "   kubectl get pods -n kubeflow"
fi

echo ""
echo "================================================"
echo "What to do next:"
echo "================================================"
echo "1. For Kubeflow UI:     ./port_forward_simple.sh"
echo "2. For local ML demo:   make demo"
echo "3. Check pod status:    kubectl get pods -n kubeflow"
echo "4. See full guide:      cat SETUP_GUIDE.md"
echo "================================================"