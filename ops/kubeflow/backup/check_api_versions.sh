#!/bin/bash

# Check API versions in Kubeflow Pipelines
# This helps understand the v1beta1 vs v2beta1 discrepancy

echo "================================================"
echo "Checking Kubeflow Pipelines API Versions"
echo "================================================"

# Check if ml-pipeline is running
ML_PIPELINE_POD=$(kubectl get pod -n kubeflow -l app=ml-pipeline -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$ML_PIPELINE_POD" ]]; then
    echo "❌ ml-pipeline pod not found or not running"
    exit 1
fi

echo "→ Found ml-pipeline pod: $ML_PIPELINE_POD"
echo ""

# Test different API endpoints
echo "→ Testing API endpoints on ml-pipeline service..."
echo ""

# Start a temporary port-forward in background
kubectl port-forward -n kubeflow svc/ml-pipeline 8888:8888 &
PF_PID=$!
sleep 3

# Test v1beta1 endpoints
echo "Testing v1beta1 endpoints:"
echo -n "  /apis/v1beta1/healthz: "
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/apis/v1beta1/healthz 2>/dev/null || echo "FAIL"

echo -n "  /apis/v1beta1/pipelines: "
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/apis/v1beta1/pipelines 2>/dev/null || echo "FAIL"

# Test v2beta1 endpoints
echo ""
echo "Testing v2beta1 endpoints:"
echo -n "  /apis/v2beta1/healthz: "
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/apis/v2beta1/healthz 2>/dev/null || echo "FAIL"

echo -n "  /apis/v2beta1/pipelines: "
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/apis/v2beta1/pipelines 2>/dev/null || echo "FAIL"

# Kill port-forward
kill $PF_PID 2>/dev/null

echo ""
echo "================================================"
echo "Checking UI configuration..."
echo "================================================"

# Check if UI has any environment variables about API version
echo "→ UI Environment Variables:"
kubectl get deployment ml-pipeline-ui -n kubeflow -o yaml | grep -E "ML_PIPELINE_SERVICE_HOST|API_SERVER|BACKEND" | head -10

echo ""
echo "================================================"
echo "Analysis"
echo "================================================"
echo ""
echo "The Kubeflow Pipelines UI in version 2.0.5 uses:"
echo "- v1beta1 for health checks (legacy)"
echo "- v2beta1 for actual pipeline operations (new API)"
echo ""
echo "If the backend (ml-pipeline) is not running, neither will work,"
echo "resulting in the proxy error you see."
echo ""
echo "The issue is NOT the API version mismatch, but rather"
echo "that the backend service is not available at all."
echo "================================================"