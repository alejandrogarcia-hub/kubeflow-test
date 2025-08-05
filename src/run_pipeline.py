"""
Script to run the Kubeflow pipeline locally or submit to Kubeflow.

This script provides options to:
- Compile the pipeline
- Run locally for testing
- Submit to Kubeflow Pipelines
"""

import argparse
import logging
from pathlib import Path

import kfp

from pipelines.iris_pipeline import compile_pipeline, iris_ml_pipeline

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def run_pipeline_locally():
    """
    Run the pipeline locally for testing.

    Note: This uses the KFP local mode which is limited
    but useful for development.
    """
    logger.info("Running pipeline locally...")

    # Create a local runner
    # Note: Local execution has limitations
    try:
        # Run with default parameters
        iris_ml_pipeline(
            n_estimators=50,  # Fewer trees for faster local testing
            test_size=0.2,
            random_state=42,
            accuracy_threshold=0.8,
            f1_threshold=0.8,
        )
        logger.info("Local pipeline execution completed")
    except Exception as e:
        logger.error(f"Local execution failed: {e}")
        logger.info("For full execution, submit to Kubeflow Pipelines")


def submit_to_kubeflow(
    pipeline_file: str = "iris_pipeline.yaml",
    experiment_name: str = "iris-classification",
    run_name: str = "iris-run",
    pipeline_params: dict | None = None,
    pipeline_name: str = "iris-classification-pipeline",
):
    """
    Submit pipeline to Kubeflow Pipelines.

    Args:
        pipeline_file: Compiled pipeline YAML file
        experiment_name: Name of the experiment
        run_name: Name of this run
        pipeline_params: Pipeline parameters
    """
    logger.info("Submitting pipeline to Kubeflow...")

    # Default parameters
    if pipeline_params is None:
        pipeline_params = {
            "n_estimators": 100,
            "test_size": 0.2,
            "random_state": 42,
            "accuracy_threshold": 0.85,
            "f1_threshold": 0.85,
            "model_name": "iris-classifier",
            "model_version": "v1.0.0",
        }

    try:
        # Create KFP client
        # Assumes port-forwarding is running: kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
        client = kfp.Client(host="http://localhost:8080")

        # Upload pipeline (if not already uploaded)
        try:
            # Try to upload pipeline
            pipeline = client.upload_pipeline(
                pipeline_package_path=pipeline_file,
                pipeline_name=pipeline_name,
                description="End-to-end ML pipeline with training, evaluation, serving, and monitoring",
            )
            pipeline_id = pipeline.pipeline_id
            logger.info(f"Pipeline uploaded with ID: {pipeline_id}")
        except Exception:
            # If pipeline exists, find it
            pipelines = client.list_pipelines()
            pipeline = None
            for p in pipelines.pipelines:
                if p.display_name == pipeline_name:
                    pipeline = p
                    pipeline_id = p.pipeline_id
                    logger.info(f"Using existing pipeline with ID: {pipeline_id}")
                    break

            if not pipeline:
                raise Exception(f"Could not find or upload pipeline {pipeline_name}")

        # Create or get experiment
        try:
            experiment = client.create_experiment(name=experiment_name)
            experiment_id = experiment.experiment_id
        except Exception:
            # If experiment exists, find it
            experiments = client.list_experiments()
            experiment = None
            for exp in experiments.experiments:
                if exp.display_name == experiment_name:
                    experiment = exp
                    experiment_id = exp.experiment_id
                    break

            if not experiment:
                raise Exception(f"Could not find experiment {experiment_name}")

        # Submit pipeline run
        run = client.run_pipeline(
            experiment_id=experiment_id,
            job_name=run_name,
            pipeline_package_path=pipeline_file,
            params=pipeline_params,
        )

        logger.info("Pipeline submitted successfully!")
        run_id = getattr(run, "run_id", None) or getattr(run, "id", None)
        logger.info(f"Run ID: {run_id}")
        logger.info(f"View in UI: http://localhost:8080/#/runs/details/{run_id}")

    except Exception as e:
        logger.error(f"Failed to submit pipeline: {e}")
        logger.info("Ensure Kubeflow Pipelines is running and port-forward is active")


def test_components():
    """
    Test individual pipeline components locally.
    """
    logger.info("Testing pipeline components...")

    # Test training component
    logger.info("Testing training component...")
    try:
        from train_model import main as train_main

        metrics = train_main(n_estimators=10)  # Small for testing
        logger.info(f"Training test passed. Metrics: {metrics}")
    except Exception as e:
        logger.error(f"Training test failed: {e}")

    # Test evaluation component
    logger.info("Testing evaluation component...")
    try:
        from evaluate_model import main as eval_main

        results = eval_main()
        logger.info(f"Evaluation test passed. Deploy: {results['deploy_model']}")
    except Exception as e:
        logger.error(f"Evaluation test failed: {e}")

    # Test monitoring component
    logger.info("Testing drift monitoring...")
    try:
        from monitor_drift import main as monitor_main

        monitoring = monitor_main()
        logger.info(f"Monitoring test passed. Status: {monitoring['overall_status']}")
    except Exception as e:
        logger.error(f"Monitoring test failed: {e}")

    logger.info("Component testing completed")


def main():
    """Main function to handle command line arguments."""
    parser = argparse.ArgumentParser(description="Run Iris ML Pipeline")
    parser.add_argument(
        "--mode",
        choices=["compile", "local", "submit", "test"],
        default="compile",
        help="Execution mode",
    )
    parser.add_argument(
        "--experiment",
        default="iris-classification",
        help="Experiment name for Kubeflow submission",
    )
    parser.add_argument(
        "--run-name", default="iris-run", help="Run name for Kubeflow submission"
    )

    args = parser.parse_args()

    if args.mode == "compile":
        logger.info("Compiling pipeline...")
        compile_pipeline("iris_pipeline.yaml")
        logger.info("Pipeline compiled successfully")

    elif args.mode == "local":
        run_pipeline_locally()

    elif args.mode == "submit":
        # First compile
        if not Path("iris_pipeline.yaml").exists():
            compile_pipeline("iris_pipeline.yaml")
        # Then submit
        submit_to_kubeflow(experiment_name=args.experiment, run_name=args.run_name)

    elif args.mode == "test":
        test_components()


if __name__ == "__main__":
    main()
