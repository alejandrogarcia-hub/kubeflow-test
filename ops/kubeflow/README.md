# Kubeflow Operations Scripts

This directory contains the essential scripts for managing Kubeflow Pipelines installation and operations.

## Main Scripts (Use These!)

### `kubeflow.sh`
The main entry point for all Kubeflow operations.

```bash
# Commands:
./kubeflow.sh install    # Clean install of Kubeflow (removes existing)
./kubeflow.sh uninstall  # Remove all Kubeflow components
./kubeflow.sh forward    # Start port forwarding to UI
./kubeflow.sh compile    # Compile the pipeline YAML
./kubeflow.sh submit     # Submit pipeline to Kubeflow
./kubeflow.sh status     # Check pod status
./kubeflow.sh demo       # Run complete demo
```

### `install_kubeflow_clean.sh`
Clean installation script that:
- Removes any existing Kubeflow installation
- Installs with SQLite backend (no MySQL issues)
- Deploys local Minio for artifact storage
- Takes ~3-5 minutes

### `uninstall_kubeflow.sh`
Completely removes all Kubeflow components from the cluster.

### `port_forward.sh`
Simple port forwarding script to access Kubeflow UI at http://localhost:8080

## Documentation

### `QUICK_REFERENCE.md`
Quick command reference for running the complete pipeline.

### `RUN_PIPELINE.md`
Detailed step-by-step guide for running pipelines with Kubeflow.

## Backup Directory

The `backup/` directory contains previous versions of scripts and alternative approaches. These are kept for reference but should not be used for normal operations.

## Typical Workflow

1. **Install Kubeflow**
   ```bash
   ./kubeflow.sh install
   ```

2. **Start UI Access**
   ```bash
   ./kubeflow.sh forward
   ```

3. **Run Demo**
   ```bash
   ./kubeflow.sh demo
   ```

4. **Clean Up**
   ```bash
   ./kubeflow.sh uninstall
   ```

## Key Features of Current Approach

- **Clean Install**: Always starts fresh, no patching
- **SQLite Backend**: No MySQL dependency issues
- **Local Storage**: Uses Minio, works reliably on Docker Desktop
- **Minimal Components**: Only what's needed for pipelines
- **Predictable**: Same result every time

## Troubleshooting

If you encounter issues:
1. Check pod status: `./kubeflow.sh status`
2. Uninstall and reinstall: `./kubeflow.sh uninstall` then `./kubeflow.sh install`
3. Ensure Docker Desktop has sufficient resources (8GB RAM, 4 CPUs)