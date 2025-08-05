#!/bin/bash

# Script to fix common ml-pipeline issues in local Kubeflow installation
# This addresses the API proxy error seen in the UI

echo "================================================"
echo "Fixing ML Pipeline Backend Issues"
echo "================================================"

# Fix MySQL image if needed
echo "→ Updating MySQL to a working image..."
kubectl set image deployment/mysql mysql=mysql:8.0 -n kubeflow

# Restart ml-pipeline pod
echo "→ Restarting ml-pipeline pod..."
kubectl delete pod -l app=ml-pipeline -n kubeflow

# Wait a moment
sleep 10

# Check status
echo ""
echo "→ Current status:"
kubectl get pods -n kubeflow | grep -E "(ml-pipeline|mysql)" | grep -v "ui"

echo ""
echo "================================================"
echo "Notes:"
echo "================================================"
echo "- The ml-pipeline pod may still crash due to MySQL"
echo "- For local development, you can:"
echo "  1. Use 'make demo' to run components locally"
echo "  2. Use the UI in view-only mode"
echo "  3. Deploy to a cloud cluster for full functionality"
echo "================================================"