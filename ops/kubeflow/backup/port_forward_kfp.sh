#!/bin/bash
echo "Starting port-forward to Kubeflow Pipelines UI..."
echo "Access the UI at: http://localhost:8080"
echo "Press Ctrl+C to stop"
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
