#!/bin/bash
echo "================================================"
echo "Kubeflow Pipelines UI Port Forward"
echo "================================================"
echo "Starting port forward to http://localhost:8080"
echo "Press Ctrl+C to stop"
echo ""
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
