# Kubeflow Pipeline - Quick Reference

## 🚀 Complete Pipeline Execution (5 Steps)

### Step 1: Install Kubeflow (Clean Install)

```bash
./ops/kubeflow/kubeflow.sh install
```

This will:
- Remove any existing Kubeflow installation
- Install fresh with SQLite backend (no MySQL issues!)
- Deploy local Minio for storage
- Takes ~3-5 minutes

### Step 2: Start Port Forward (New Terminal)

```bash
./ops/kubeflow/kubeflow.sh forward
```

Keep this running!

### Step 3: Run the Demo

```bash
./ops/kubeflow/kubeflow.sh demo
```

This will compile and submit the pipeline

### Step 4: Monitor in UI

- Open <http://localhost:8080>
- Navigate to: Experiments → iris-demo → Your Run
- Watch components turn green as they complete

### Step 5: Test Results

```bash
# After pipeline completes
make serve

# In another terminal
curl -X POST "http://localhost:8000/predict" \
  -H "Content-Type: application/json" \
  -d '{"sepal_length": 5.1, "sepal_width": 3.5, "petal_length": 1.4, "petal_width": 0.2}'
```

## 📁 File Organization

```
ops/kubeflow/
├── kubeflow.sh         # Main script (use this!)
├── install_kubeflow.sh # Installation script
├── port_forward.sh     # Port forwarding
├── RUN_PIPELINE.md     # Detailed guide
├── QUICK_REFERENCE.md  # This file
└── backup/             # Other scripts (ignore)
```

## 🔧 Individual Commands

```bash
# Check status
./ops/kubeflow/kubeflow.sh status

# Just compile pipeline
./ops/kubeflow/kubeflow.sh compile

# Just submit pipeline
./ops/kubeflow/kubeflow.sh submit

# Help
./ops/kubeflow/kubeflow.sh help
```

## 🚨 Common Issues

| Issue | Solution |
|-------|----------|
| UI shows API error | Normal for local setup, UI still viewable |
| Pods in CrashLoop | Expected, doesn't block pipeline viewing |
| Port 8080 in use | Kill process: `lsof -ti:8080 \| xargs kill` |
| Pipeline won't submit | Check if port-forward is running |

## 💡 Tips

1. **Always run port-forward in separate terminal**
2. **UI errors are expected** - View mode still works
3. **For full functionality** - Deploy to cloud Kubernetes
4. **To skip Kubeflow** - Use `make demo` for local ML only

## 🎯 Success Indicators

- ✅ All pipeline components green in UI
- ✅ Files in `models/` directory
- ✅ API returns predictions
- ✅ Accuracy > 85% in evaluation
