#!/bin/bash

# Script to view logs for Kubeflow pipeline runs

echo "================================================"
echo "Kubeflow Pipeline Logs Viewer"
echo "================================================"

# Get workflow name from user or use latest
if [ -z "$1" ]; then
    echo "Fetching latest workflow..."
    WORKFLOW=$(kubectl get workflows -n kubeflow --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
    if [ -z "$WORKFLOW" ]; then
        echo "No workflows found"
        exit 1
    fi
    echo "Latest workflow: $WORKFLOW"
else
    WORKFLOW=$1
fi

echo ""
echo "Workflow: $WORKFLOW"
echo "================================================"

# Show workflow status
echo "Status:"
kubectl get workflow $WORKFLOW -n kubeflow -o jsonpath='{.status.phase}'
echo ""
echo ""

# List all pods for this workflow
echo "Pods:"
kubectl get pods -n kubeflow -l workflows.argoproj.io/workflow=$WORKFLOW --no-headers

echo ""
echo "================================================"
echo "Container Logs:"
echo "================================================"

# Get logs from all pods
for pod in $(kubectl get pods -n kubeflow -l workflows.argoproj.io/workflow=$WORKFLOW -o jsonpath='{.items[*].metadata.name}'); do
    echo ""
    echo "--- Pod: $pod ---"
    
    # Get main container logs
    echo "Main container logs:"
    kubectl logs $pod -n kubeflow -c main 2>/dev/null || echo "No main container logs"
    
    # Get kfp-launcher logs if exists
    echo ""
    echo "KFP launcher logs:"
    kubectl logs $pod -n kubeflow -c kfp-launcher 2>/dev/null || echo "No launcher logs"
    
    echo "================================================"
done

echo ""
echo "To view specific pod logs:"
echo "kubectl logs <pod-name> -n kubeflow -c main"
echo "kubectl logs <pod-name> -n kubeflow -c kfp-launcher"