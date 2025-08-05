# Kubeflow ML Pipeline - Complete Setup Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Installation Order](#installation-order)
3. [Step-by-Step Setup](#step-by-step-setup)
4. [Troubleshooting Common Issues](#troubleshooting-common-issues)
5. [Running the Demo](#running-the-demo)
6. [Architecture Overview](#architecture-overview)

## Prerequisites

- macOS with Docker Desktop installed
- Kubernetes enabled in Docker Desktop
- kubectl configured
- Python 3.13+
- uv package manager

## Installation Order

**IMPORTANT: Follow these steps in order:**

1. Verify Kubernetes is running
2. Install Kubeflow Pipelines
3. Fix any pod issues
4. Access the UI
5. Run pipeline components

## Step-by-Step Setup

### 1. Verify Prerequisites

```bash
# Check Docker is running
docker version

# Check Kubernetes is running
kubectl cluster-info

# Should show:
# Kubernetes control plane is running at https://127.0.0.1:xxxxx

# Check nodes
kubectl get nodes
# Should show 2 nodes: desktop-control-plane and desktop-worker
```

### 2. Install Python Dependencies

```bash
# Install project dependencies
uv sync

# Verify installation
uv run python --version
# Should show Python 3.13+
```

### 3. Install Kubeflow Pipelines

We have two installation options:

#### Option A: Quick Install (Recommended for Demo)
```bash
# This script creates namespace and installs KFP
./scripts/install_kfp_quick.sh

# Wait for pods to stabilize (5-10 minutes)
kubectl get pods -n kubeflow -w
```

#### Option B: Standard Install
```bash
# Use if Option A fails
./scripts/install_kfp_working.sh
```

### 4. Check Installation Status

```bash
# Check all pods
kubectl get pods -n kubeflow

# Expected: ml-pipeline-ui should be Running
# Note: Some pods may be in CrashLoopBackOff - this is normal for local setup
```

### 5. Access Kubeflow UI

```bash
# Start port forwarding
./port_forward_kfp.sh

# Open browser at http://localhost:8080
```

## Troubleshooting Common Issues

### Issue 1: "Error occurred while trying to proxy" in UI

**Cause**: The ml-pipeline backend pod is not running properly.

**Solution**:
```bash
# Check backend status
kubectl get pod -n kubeflow -l app=ml-pipeline

# If CrashLoopBackOff, it's likely due to MySQL
# For demo purposes, we can use the UI in limited mode
# Most viewing features will work, but creating new pipelines may fail
```

### Issue 2: MySQL ImagePullBackOff

**Cause**: The MySQL image specified in KFP 2.0.5 may not be available.

**Quick Fix**:
```bash
# Update MySQL deployment to use a working image
kubectl set image deployment/mysql mysql=mysql:8.0 -n kubeflow
```

### Issue 3: Multiple pods in CrashLoopBackOff

**Solution**: For local development, we can work around this:
```bash
# The UI will still work for viewing
# For full functionality, use Option A in the next section
```

## Running the Demo

### Option A: Local Pipeline Execution (No Kubernetes Required)

```bash
# 1. Train the model
make train
# Creates model artifacts in models/

# 2. Evaluate the model
make evaluate
# Checks model performance

# 3. Start model serving API
make serve
# Access at http://localhost:8000/docs

# 4. Test prediction
curl -X POST "http://localhost:8000/predict" \
  -H "Content-Type: application/json" \
  -d '{
    "sepal_length": 5.1,
    "sepal_width": 3.5,
    "petal_length": 1.4,
    "petal_width": 0.2
  }'

# 5. Run drift monitoring
make monitor
```

### Option B: Submit to Kubeflow (Requires Working Installation)

```bash
# 1. Compile pipeline
make compile

# 2. Submit to Kubeflow
make submit

# 3. View in UI at http://localhost:8080
```

## Architecture Overview

```
Project Structure:
├── src/                    # Pipeline components
│   ├── train_model.py     # Training logic
│   ├── evaluate_model.py  # Evaluation logic
│   ├── serve_model.py     # FastAPI serving
│   └── monitor_drift.py   # Drift detection
├── pipelines/             # Kubeflow pipeline definitions
├── scripts/               # Installation scripts
└── notebooks/             # Jupyter notebooks

Data Flow:
1. Training: Load Iris → Train RF → Save Model
2. Evaluation: Load Model → Evaluate → Deploy Decision
3. Serving: FastAPI → Load Model → Predict
4. Monitoring: Compare Distributions → Detect Drift
```

## Quick Commands Reference

```bash
# Installation
make install          # Install Python dependencies
./scripts/install_kfp_quick.sh  # Install Kubeflow

# Development
make train           # Train model
make evaluate        # Evaluate model
make serve          # Start API server
make monitor        # Run drift detection
make demo           # Run train + evaluate

# Kubeflow
make compile        # Compile pipeline
make submit         # Submit to Kubeflow
make kf-status      # Check Kubeflow pods

# Utilities
make format         # Format code
make lint          # Lint code
make test          # Run tests
make clean         # Clean artifacts
```

## Next Steps

1. **For Learning Kubeflow**: Focus on the pipeline code in `pipelines/iris_pipeline.py`
2. **For ML Development**: Modify components in `src/`
3. **For Production**: Deploy to a cloud Kubernetes cluster with proper resources

## Getting Help

- Check `TROUBLESHOOTING.md` for more detailed solutions
- Review pod logs: `kubectl logs <pod-name> -n kubeflow`
- Kubeflow docs: https://www.kubeflow.org/docs/