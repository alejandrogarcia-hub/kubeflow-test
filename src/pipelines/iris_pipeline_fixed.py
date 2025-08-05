"""
Kubeflow Pipeline for end-to-end Iris classification - Fixed version.

This version works around the metadata tracking issue by:
1. Combining train and evaluate into a single component
2. Using explicit artifact URIs instead of metadata resolution
"""

import kfp
from kfp import dsl
from kfp.dsl import (
    Artifact,
    Input,
    Metrics,
    Model,
    Output,
    OutputPath,
    component,
)


@component(
    base_image="python:3.11-slim",
    packages_to_install=[
        "scikit-learn==1.5.2",
        "pandas==2.2.3",
        "numpy==1.26.4",
        "minio==7.2.10",
    ],
)
def train_and_evaluate_iris(
    n_estimators: int,
    test_size: float,
    random_state: int,
    accuracy_threshold: float,
    f1_threshold: float,
    model: Output[Model],
    scaler: Output[Artifact],
    metrics: Output[Metrics],
    evaluation_report: Output[Artifact],
) -> str:
    """
    Combined training and evaluation component to avoid metadata tracking issues.

    Returns:
        str: "deploy" or "no-deploy" based on thresholds
    """
    import json
    import pickle
    from pathlib import Path

    import pandas as pd
    from sklearn.datasets import load_iris
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, classification_report, f1_score
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import StandardScaler

    print(f"Training model with {n_estimators} estimators")

    # Load data
    iris = load_iris()
    X = pd.DataFrame(iris.data, columns=iris.feature_names)
    y = pd.Series(iris.target)

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )

    # Scale features
    scaler_obj = StandardScaler()
    X_train_scaled = scaler_obj.fit_transform(X_train)
    X_test_scaled = scaler_obj.transform(X_test)

    # Train model
    rf_model = RandomForestClassifier(
        n_estimators=n_estimators, random_state=random_state
    )
    rf_model.fit(X_train_scaled, y_train)

    # Calculate training metrics
    train_score = rf_model.score(X_train_scaled, y_train)
    test_score = rf_model.score(X_test_scaled, y_test)

    # Save model and scaler
    Path(model.path).parent.mkdir(parents=True, exist_ok=True)
    with open(model.path, "wb") as f:
        pickle.dump(rf_model, f)

    Path(scaler.path).parent.mkdir(parents=True, exist_ok=True)
    with open(scaler.path, "wb") as f:
        pickle.dump(scaler_obj, f)

    # Evaluate model
    print("Evaluating model performance...")
    y_pred = rf_model.predict(X_test_scaled)

    # Calculate evaluation metrics
    accuracy = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, average="weighted")

    # Log all metrics
    metrics.log_metric("train_accuracy", train_score)
    metrics.log_metric("test_accuracy", test_score)
    metrics.log_metric("n_features", X.shape[1])
    metrics.log_metric("n_training_samples", len(X_train))
    metrics.log_metric("evaluation_accuracy", accuracy)
    metrics.log_metric("evaluation_f1_score", f1)
    metrics.log_metric("accuracy_threshold", accuracy_threshold)
    metrics.log_metric("f1_threshold", f1_threshold)

    # Make deployment decision
    deploy = accuracy >= accuracy_threshold and f1 >= f1_threshold
    deploy_decision = "deploy" if deploy else "no-deploy"

    metrics.log_metric("deployment_decision", 1 if deploy else 0)

    # Generate evaluation report
    report = {
        "train_accuracy": train_score,
        "test_accuracy": test_score,
        "accuracy": accuracy,
        "f1_score": f1,
        "accuracy_threshold": accuracy_threshold,
        "f1_threshold": f1_threshold,
        "deploy_decision": deploy_decision,
        "classification_report": classification_report(
            y_test, y_pred, target_names=iris.target_names.tolist(), output_dict=True
        ),
    }

    # Save report
    with open(evaluation_report.path, "w") as f:
        json.dump(report, f, indent=2)

    print(f"Training complete - Test accuracy: {test_score:.4f}")
    print(f"Evaluation complete - Deploy: {deploy_decision}")

    return deploy_decision


@component(base_image="python:3.11-slim", packages_to_install=["minio==7.2.10"])
def prepare_model_serving(
    model: Input[Model],
    scaler: Input[Artifact],
    deploy_decision: str,
    serving_uri: OutputPath(str),
) -> None:
    """
    Prepare model for serving with KServe.

    This component packages the model and uploads to storage.
    """
    import shutil
    from pathlib import Path

    print(f"Preparing model for serving (deploy decision: {deploy_decision})...")

    if deploy_decision != "deploy":
        print("Model not approved for deployment")
        with open(serving_uri, "w") as f:
            f.write("not-deployed")
        return

    # Create serving directory
    serving_path = Path("/tmp/model_serving")
    serving_path.mkdir(parents=True, exist_ok=True)

    # Copy model artifacts
    shutil.copy(model.path, serving_path / "model.pkl")
    shutil.copy(scaler.path, serving_path / "scaler.pkl")

    # In production, upload to S3/GCS/MinIO
    # For now, just save the local path
    with open(serving_uri, "w") as f:
        f.write(str(serving_path))

    print(f"Model prepared for serving at: {serving_path}")


@component(
    base_image="python:3.11-slim",
    packages_to_install=["evidently==0.4.40", "pandas==2.2.3", "scikit-learn==1.5.2"],
)
def setup_drift_monitoring(
    model: Input[Model], deploy_decision: str, monitoring_config: Output[Artifact]
) -> None:
    """
    Setup drift monitoring configuration.

    Creates baseline data and monitoring configuration.
    """
    import json

    import pandas as pd
    from sklearn.datasets import load_iris
    from sklearn.model_selection import train_test_split

    print(f"Setting up drift monitoring (deploy decision: {deploy_decision})...")

    if deploy_decision != "deploy":
        print("Model not deployed, skipping monitoring setup")
        config = {"status": "not-deployed"}
    else:
        # Load data for baseline
        iris = load_iris()
        X = pd.DataFrame(iris.data, columns=iris.feature_names)
        y = pd.Series(iris.target)

        # Use training data as baseline
        X_train, _, y_train, _ = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y
        )

        # Create monitoring configuration
        config = {
            "baseline_size": len(X_train),
            "features": list(iris.feature_names),
            "drift_threshold": 0.5,
            "monitoring_frequency": "daily",
            "alert_channels": ["email", "slack"],
            "status": "active",
        }

    # Save configuration
    with open(monitoring_config.path, "w") as f:
        json.dump(config, f, indent=2)

    print("Drift monitoring configured")


@component(base_image="python:3.11-slim", packages_to_install=["pydantic==2.11.0"])
def register_model(
    model: Input[Model],
    evaluation_report: Input[Artifact],
    deploy_decision: str,
    model_name: str,
    model_version: str,
    registry_entry: Output[Artifact],
) -> None:
    """
    Register model in the model registry.

    Creates model registry entry with metadata.
    """
    import json
    from datetime import datetime

    print(
        f"Registering model: {model_name} v{model_version} (deploy: {deploy_decision})"
    )

    # Load evaluation report
    with open(evaluation_report.path) as f:
        eval_report = json.load(f)

    # Create registry entry
    registry_metadata = {
        "model_name": model_name,
        "model_version": model_version,
        "model_path": model.path,
        "registered_at": datetime.now().isoformat(),
        "framework": "scikit-learn",
        "algorithm": "RandomForestClassifier",
        "metrics": {
            "accuracy": eval_report["accuracy"],
            "f1_score": eval_report["f1_score"],
            "train_accuracy": eval_report["train_accuracy"],
            "test_accuracy": eval_report["test_accuracy"],
        },
        "status": (
            "production-ready" if deploy_decision == "deploy" else "evaluation-only"
        ),
        "deployed": deploy_decision == "deploy",
        "tags": ["iris", "classification", "ml-pipeline"],
    }

    # Save registry entry
    with open(registry_entry.path, "w") as f:
        json.dump(registry_metadata, f, indent=2)

    print("Model registered successfully")


@dsl.pipeline(
    name="Iris Classification Pipeline Fixed",
    description="End-to-end ML pipeline that works around metadata tracking issues",
)
def iris_ml_pipeline_fixed(
    n_estimators: int = 100,
    test_size: float = 0.2,
    random_state: int = 42,
    accuracy_threshold: float = 0.85,
    f1_threshold: float = 0.85,
    model_name: str = "iris-classifier",
    model_version: str = "v1.0.0",
):
    """
    Complete ML pipeline for Iris classification.

    This version combines train and evaluate to avoid metadata tracking issues.
    """

    # Step 1: Train and evaluate the model in one step
    train_eval_task = train_and_evaluate_iris(
        n_estimators=n_estimators,
        test_size=test_size,
        random_state=random_state,
        accuracy_threshold=accuracy_threshold,
        f1_threshold=f1_threshold,
    )

    # Step 2: Prepare for serving (depends on deploy decision)
    _ = prepare_model_serving(
        model=train_eval_task.outputs["model"],
        scaler=train_eval_task.outputs["scaler"],
        deploy_decision=train_eval_task.outputs["Output"],
    )

    # Step 3: Setup monitoring
    _ = setup_drift_monitoring(
        model=train_eval_task.outputs["model"],
        deploy_decision=train_eval_task.outputs["Output"],
    )

    # Step 4: Register model
    _ = register_model(
        model=train_eval_task.outputs["model"],
        evaluation_report=train_eval_task.outputs["evaluation_report"],
        deploy_decision=train_eval_task.outputs["Output"],
        model_name=model_name,
        model_version=model_version,
    )


def compile_pipeline(output_file: str = "iris_pipeline_fixed.yaml"):
    """
    Compile the pipeline to YAML format.

    Args:
        output_file: Output filename for compiled pipeline
    """
    kfp.compiler.Compiler().compile(
        pipeline_func=iris_ml_pipeline_fixed, package_path=output_file
    )
    print(f"Pipeline compiled to: {output_file}")


if __name__ == "__main__":
    # Compile the pipeline
    compile_pipeline()
