#!/bin/bash

# Uninstall Kubeflow completely

echo "================================================"
echo "Uninstalling Kubeflow"
echo "================================================"

read -p "This will remove ALL Kubeflow components. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo "→ Deleting kubeflow namespace..."
kubectl delete namespace kubeflow --ignore-not-found=true --wait=true --timeout=120s || {
    echo "  Force deleting..."
    kubectl delete namespace kubeflow --ignore-not-found=true --force --grace-period=0 || true
}

echo "→ Cleaning up cluster resources..."
kubectl delete clusterrolebinding -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true
kubectl delete clusterrole -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true
kubectl delete crd -l app.kubernetes.io/part-of=kubeflow --ignore-not-found=true 2>/dev/null || true

echo ""
echo "✓ Kubeflow uninstalled successfully"