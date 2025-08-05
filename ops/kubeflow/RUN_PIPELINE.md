# Running the Complete Kubeflow Pipeline - Step by Step

## Prerequisites Check

```bash
# 1. Verify Docker Desktop is running
docker version

# 2. Verify Kubernetes is enabled
kubectl cluster-info

# 3. Verify Python environment
uv run python --version  # Should show 3.13+
```

## Step 1: Install Kubeflow Pipelines

```bash
# From project root directory
cd /Users/alejandro/workspace/kubeflow-test

# Install Kubeflow (takes 5-10 minutes)
./ops/kubeflow/install_kubeflow.sh

# Wait for installation to complete
# You'll see "✅ UI is ready!" when done
```

## Step 2: Start Port Forwarding

```bash
# In a separate terminal window
./ops/kubeflow/port_forward.sh

# Keep this running - it forwards localhost:8080 to Kubeflow
```

## Step 3: Compile the Pipeline

```bash
# In your main terminal
uv run python pipelines/iris_pipeline.py

# This creates: iris_pipeline.yaml
# Verify it exists:
ls -la iris_pipeline.yaml
```

## Step 4: Submit Pipeline to Kubeflow

### Option A: Using the Script
```bash
# Submit pipeline with default parameters
uv run python run_pipeline.py --mode submit \
  --experiment "iris-demo" \
  --run-name "iris-run-$(date +%Y%m%d-%H%M%S)"
```

### Option B: Using the UI
1. Open http://localhost:8080
2. Click "Pipelines" → "Upload Pipeline"
3. Upload `iris_pipeline.yaml`
4. Create a new experiment called "iris-demo"
5. Create a run with these parameters:
   - n_estimators: 100
   - test_size: 0.2
   - accuracy_threshold: 0.85
   - model_name: "iris-classifier"

## Step 5: Monitor Pipeline Execution

### In the UI:
1. Go to "Experiments" → "iris-demo"
2. Click on your run
3. Watch the pipeline progress:
   - Green = Completed
   - Blue = Running
   - Red = Failed

### Expected Pipeline Flow:
```
Train Model (2-3 min)
    ↓
Evaluate Model (1 min)
    ↓
[If accuracy > 0.85]
    ↓
Deploy Components:
- Prepare Serving
- Setup Monitoring  
- Register Model
```

## Step 6: View Results

### In Kubeflow UI:
1. Click on any completed component
2. View "Logs" tab for execution details
3. View "Metrics" tab for performance metrics
4. View "Artifacts" for saved files

### Check Artifacts Locally:
```bash
# Model artifacts are saved in:
ls -la models/

# Should see:
# - model.pkl (trained model)
# - scaler.pkl (data preprocessor)
# - metrics.json (performance metrics)
# - evaluation_report.json (if evaluation passed)
```

## Step 7: Test the Deployed Model

If the pipeline completed successfully:

```bash
# Start the model serving API
make serve

# In another terminal, test prediction:
curl -X POST "http://localhost:8000/predict" \
  -H "Content-Type: application/json" \
  -d '{
    "sepal_length": 5.1,
    "sepal_width": 3.5,
    "petal_length": 1.4,
    "petal_width": 0.2
  }'

# Expected response:
# {
#   "prediction": "setosa",
#   "confidence": 0.98,
#   ...
# }
```

## Troubleshooting

### Issue: "Error occurred while trying to proxy" in UI
- **Expected for local setup** - The UI still works for viewing
- Backend pods may be crashing but pipeline runs are stored

### Issue: Pipeline fails at Train Model
```bash
# Check pod logs
kubectl get pods -n kubeflow | grep pipeline
kubectl logs <pod-name> -n kubeflow
```

### Issue: Cannot submit pipeline
- Ensure `iris_pipeline.yaml` exists
- Try uploading through UI instead of CLI

## Complete Command Sequence

```bash
# Terminal 1 - Setup
cd /Users/alejandro/workspace/kubeflow-test
./ops/kubeflow/install_kubeflow.sh
# Wait for "✅ UI is ready!"

# Terminal 2 - Port Forward (keep running)
./ops/kubeflow/port_forward.sh

# Terminal 1 - Run Pipeline
uv run python pipelines/iris_pipeline.py
uv run python run_pipeline.py --mode submit

# Open browser
open http://localhost:8080

# After pipeline completes, test locally
make serve
# Terminal 3 - test API
curl -X POST "http://localhost:8000/predict" \
  -H "Content-Type: application/json" \
  -d '{"sepal_length": 5.1, "sepal_width": 3.5, "petal_length": 1.4, "petal_width": 0.2}'
```

## Pipeline Parameters

You can customize the pipeline by modifying these parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| n_estimators | 100 | Number of trees in Random Forest |
| test_size | 0.2 | Fraction of data for testing |
| accuracy_threshold | 0.85 | Minimum accuracy for deployment |
| f1_threshold | 0.85 | Minimum F1 score for deployment |
| model_name | "iris-classifier" | Name in model registry |
| model_version | "v1.0.0" | Version tag |

## Success Criteria

You'll know the pipeline ran successfully when:
1. ✅ All components show green in the UI
2. ✅ `models/` directory contains model artifacts
3. ✅ API returns predictions when tested
4. ✅ Evaluation metrics show accuracy > 85%

## Next Steps

1. **Modify the pipeline**: Edit `pipelines/iris_pipeline.py`
2. **Add new components**: Create new functions with `@component` decorator
3. **Use different models**: Modify `src/train_model.py`
4. **Deploy to cloud**: Use GKE, EKS, or AKS for production