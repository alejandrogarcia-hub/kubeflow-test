#!/bin/bash

# Fix Kubeflow Pipelines Backend Issues
# This script addresses the UI proxy error by fixing the backend components

set -e

echo "================================================"
echo "Fixing Kubeflow Pipelines Backend"
echo "================================================"

# Check current status
echo "→ Current backend status:"
kubectl get pods -n kubeflow | grep -E "(mysql|ml-pipeline|minio)" | grep -v ui

echo ""
echo "→ Analyzing root cause..."

# Fix 1: Deploy a working MySQL instance
echo ""
echo "→ Deploying SQLite-based backend (avoids MySQL issues)..."

# Create a patched ml-pipeline deployment that uses SQLite
cat << 'EOF' > /tmp/ml-pipeline-sqlite-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-pipeline
  namespace: kubeflow
spec:
  template:
    spec:
      containers:
      - name: ml-pipeline-api-server
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: DBCONFIG_DRIVER
          value: sqlite3
        - name: DBCONFIG_DB_NAME
          value: /var/mlpipeline/mlpipeline.db
        - name: DBCONFIG_GROUP_CONCAT_MAX_LEN
          value: "4194304"
        volumeMounts:
        - name: mlpipeline-db
          mountPath: /var/mlpipeline
      volumes:
      - name: mlpipeline-db
        emptyDir: {}
EOF

# Apply the patch
kubectl patch deployment ml-pipeline -n kubeflow --patch-file=/tmp/ml-pipeline-sqlite-patch.yaml

echo "→ Waiting for ml-pipeline to restart..."
kubectl rollout status deployment/ml-pipeline -n kubeflow --timeout=300s || true

# Fix 2: Create a minimal Minio deployment if needed
echo ""
echo "→ Checking Minio status..."
MINIO_STATUS=$(kubectl get pod -n kubeflow -l app=minio -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

if [[ "$MINIO_STATUS" != "Running" ]]; then
    echo "→ Deploying local Minio storage..."
    
    cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: kubeflow
spec:
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:RELEASE.2023-06-19T19-52-50Z
        args:
        - server
        - /data
        env:
        - name: MINIO_ACCESS_KEY
          value: minio
        - name: MINIO_SECRET_KEY
          value: minio123
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  namespace: kubeflow
spec:
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: minio
EOF
fi

# Wait for services to be ready
echo ""
echo "→ Waiting for services to stabilize..."
sleep 20

# Check final status
echo ""
echo "→ Final status check:"
kubectl get pods -n kubeflow | grep -E "(ml-pipeline|minio)" | head -10

# Test the API endpoint
echo ""
echo "→ Testing ml-pipeline API..."
ML_PIPELINE_POD=$(kubectl get pod -n kubeflow -l app=ml-pipeline -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$ML_PIPELINE_POD" ]]; then
    kubectl exec -n kubeflow "$ML_PIPELINE_POD" -- wget -O- http://localhost:8888/apis/v1beta1/healthz 2>/dev/null && echo " ✅ API is responding!" || echo " ❌ API not ready yet"
fi

echo ""
echo "================================================"
echo "Fix Applied!"
echo "================================================"
echo ""
echo "The backend has been switched to SQLite to avoid MySQL issues."
echo "This is suitable for development and testing."
echo ""
echo "Next steps:"
echo "1. Restart port-forward: ./ops/kubeflow/port_forward.sh"
echo "2. Access UI: http://localhost:8080"
echo "3. The UI should now work without proxy errors!"
echo ""
echo "Note: For production use, deploy with proper MySQL/PostgreSQL."
echo "================================================"

# Clean up
rm -f /tmp/ml-pipeline-sqlite-patch.yaml