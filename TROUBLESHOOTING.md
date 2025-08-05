# Troubleshooting Guide

## Issue: "Unable to connect to the server: EOF"

This error indicates that the Kubernetes cluster is not accessible. Here's how to fix it:

### Solution 1: Restart Docker Desktop Kubernetes

1. **Open Docker Desktop**
   - Click on the Docker icon in your menu bar
   - Go to Settings/Preferences

2. **Reset Kubernetes**
   - Navigate to the "Kubernetes" tab
   - Ensure "Enable Kubernetes" is checked
   - Click "Apply & Restart" or "Reset Kubernetes Cluster"

3. **Wait for Kubernetes to Start**
   - This can take 2-5 minutes
   - The Docker icon will show "Kubernetes is running" when ready

4. **Verify Connection**
   ```bash
   kubectl cluster-info
   ```

### Solution 2: Quick Restart (Command Line)

```bash
# Restart Docker Desktop
osascript -e 'quit app "Docker Desktop"'
sleep 5
open -a "Docker Desktop"

# Wait for Docker to start (about 30-60 seconds)
sleep 60

# Check if Kubernetes is running
kubectl cluster-info
```

### Solution 3: Manual Kubernetes Context Fix

```bash
# List available contexts
kubectl config get-contexts

# Set to docker-desktop context
kubectl config use-context docker-desktop

# Test connection
kubectl get nodes
```

## After Kubernetes is Running

Once Kubernetes is back up, you'll need to reinstall Kubeflow Pipelines:

```bash
# Check if any Kubeflow resources exist
kubectl get namespace kubeflow

# If namespace doesn't exist, install Kubeflow Pipelines
./scripts/install_kfp_working.sh

# Wait for pods to be ready (this takes several minutes)
kubectl wait --for=condition=available --timeout=600s deployment/ml-pipeline-ui -n kubeflow

# Then try port-forwarding again
./port_forward_kfp.sh
```

## Alternative: Run Components Locally

While waiting for Kubernetes, you can still test the ML pipeline components locally:

```bash
# Train the model
make train

# Evaluate the model
make evaluate

# Start the serving API
make serve
# In another terminal, test the API:
curl -X POST "http://localhost:8000/predict" \
  -H "Content-Type: application/json" \
  -d '{
    "sepal_length": 5.1,
    "sepal_width": 3.5,
    "petal_length": 1.4,
    "petal_width": 0.2
  }'

# Run drift monitoring
make monitor
```

## Common Issues

### Issue: Kubeflow pods in CrashLoopBackOff
This is common with local installations. The UI usually still works:
```bash
# Check pod status
kubectl get pods -n kubeflow

# Even if some pods are failing, try accessing the UI
./port_forward_kfp.sh
```

### Issue: Port 8080 already in use
```bash
# Find what's using port 8080
lsof -i :8080

# Kill the process or use a different port
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8081:80
```

### Issue: Insufficient resources
Docker Desktop needs sufficient resources for Kubernetes and Kubeflow:
1. Open Docker Desktop Settings
2. Go to Resources
3. Recommended settings:
   - CPUs: 4+
   - Memory: 8GB+
   - Disk: 50GB+