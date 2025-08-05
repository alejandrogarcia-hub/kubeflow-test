# Fixing Kubeflow UI Proxy Error

## Understanding the Issue

The error `Error occured while trying to proxy to: localhost:8080/apis/v2beta1/pipelines` occurs because:

1. The UI (ml-pipeline-ui) is running and accessible
2. The backend API (ml-pipeline) is crashing due to MySQL connection issues
3. The UI cannot proxy requests to the non-existent backend

## API Version Clarification

You may notice that:
- The error shows `/apis/v2beta1/pipelines` (new API)
- Health checks use `/apis/v1beta1/healthz` (legacy endpoint)

This is **normal behavior** in Kubeflow Pipelines 2.0.5:
- Health monitoring still uses v1beta1 endpoints
- Actual pipeline operations use v2beta1 endpoints
- Both would work if the backend was running

## Root Cause Analysis

```
UI (port 8080) → tries to proxy → Backend API (port 8888) ❌
                     ↓                        ↓
              v2beta1 (pipelines)      Needs MySQL ❌
              v1beta1 (healthz)        (ImagePullBackOff)
```

## Solutions

### Solution 1: Quick Fix with SQLite (Recommended for Local Dev)

Run this script to switch the backend to SQLite:

```bash
./ops/kubeflow/fix_pipeline_backend.sh
```

This will:
- Patch ml-pipeline to use SQLite instead of MySQL
- Deploy a local Minio if needed
- Avoid external dependencies

### Solution 2: Fix MySQL Deployment

```bash
# Update MySQL to a working image
kubectl set image deployment/mysql mysql=mysql:5.7 -n kubeflow

# Wait for MySQL to start
kubectl wait --for=condition=available deployment/mysql -n kubeflow --timeout=300s

# Restart ml-pipeline
kubectl rollout restart deployment/ml-pipeline -n kubeflow
```

### Solution 3: Use External Database

For production-like setup, configure ml-pipeline to use an external database:

```yaml
# Edit ml-pipeline deployment
kubectl edit deployment ml-pipeline -n kubeflow

# Add these environment variables:
- name: DBCONFIG_DRIVER
  value: mysql
- name: DBCONFIG_MYSQLCONFIG_HOST
  value: your-mysql-host
- name: DBCONFIG_MYSQLCONFIG_PORT
  value: "3306"
- name: DBCONFIG_MYSQLCONFIG_USER
  value: root
- name: DBCONFIG_MYSQLCONFIG_PASSWORD
  value: your-password
```

## Verification

After applying any fix:

1. Check backend status:
```bash
kubectl get pods -n kubeflow -l app=ml-pipeline
# Should show Running
```

2. Test API endpoints:
```bash
# Run the API version check
./ops/kubeflow/check_api_versions.sh

# Or manually test:
kubectl port-forward -n kubeflow svc/ml-pipeline 8888:8888 &
curl http://localhost:8888/apis/v1beta1/healthz  # Should return OK
curl http://localhost:8888/apis/v2beta1/pipelines  # Should return JSON
```

3. Restart UI port-forward:
```bash
# Kill existing port-forward
pkill -f "port-forward.*ml-pipeline-ui"

# Start fresh
./ops/kubeflow/port_forward.sh
```

4. Access UI at http://localhost:8080
   - Should load without proxy errors
   - Can create and view pipelines

## Why This Happens in Local Deployments

1. **Resource Constraints**: Docker Desktop has limited resources
2. **Image Issues**: Some images (MySQL 8.0) have compatibility issues
3. **Storage**: Persistent volumes work differently in Docker Desktop

## Best Practices for Local Development

1. **Use SQLite backend** for simplicity
2. **Allocate sufficient Docker resources**:
   - Memory: 8GB+
   - CPUs: 4+
   
3. **Consider alternatives**:
   - Use KFP SDK directly without full deployment
   - Use Kind with custom configuration
   - Deploy to cloud for full features

## The Complete Fix

```bash
# 1. Apply the fix
./ops/kubeflow/fix_pipeline_backend.sh

# 2. Wait for pods to stabilize (2-3 minutes)
kubectl get pods -n kubeflow -w

# 3. Restart port-forward
./ops/kubeflow/port_forward.sh

# 4. Access UI - should work without errors!
open http://localhost:8080
```

## Summary

The UI proxy error is caused by the backend API server (ml-pipeline) not running due to database connectivity issues. The v1beta1 vs v2beta1 difference is normal - the UI uses both API versions for different purposes. By switching to SQLite or fixing the MySQL deployment, we can resolve this issue and get a fully functional Kubeflow Pipelines UI for local development.