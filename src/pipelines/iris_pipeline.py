"""
Kubeflow Pipeline for end-to-end Iris classification.

This pipeline demonstrates:
- Model training with hyperparameters
- Model evaluation with thresholds
- Conditional deployment based on performance
- Model serving preparation
- Drift monitoring setup
"""

import os
from typing import NamedTuple

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


# Define component outputs using NamedTuple
class TrainingOutput(NamedTuple):
    """Output structure for training component."""

    model: Output[Model]
    scaler: Output[Artifact]
    metrics: Output[Metrics]
    model_dir: OutputPath(str)


class EvaluationOutput(NamedTuple):
    """Output structure for evaluation component."""

    deploy_decision: str
    evaluation_report: Output[Artifact]
    metrics: Output[Metrics]


@component(
    base_image="python:3.11-slim",
    packages_to_install=["scikit-learn==1.5.2", "pandas==2.2.3", "numpy==1.26.4"],
)
def train_iris_model(
    n_estimators: int,
    test_size: float,
    random_state: int,
    model: Output[Model],
    scaler: Output[Artifact],
    metrics: Output[Metrics],
) -> str:
    """
    Train Iris classification model.

    This component:
    - Loads the Iris dataset
    - Splits data into train/test
    - Trains a Random Forest model
    - Saves model artifacts
    - Records metrics
    """
    import json
    import pickle
    from pathlib import Path

    import pandas as pd
    from sklearn.datasets import load_iris
    from sklearn.ensemble import RandomForestClassifier
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

    # Calculate metrics
    train_score = rf_model.score(X_train_scaled, y_train)
    test_score = rf_model.score(X_test_scaled, y_test)

    # Save model
    Path(model.path).parent.mkdir(parents=True, exist_ok=True)
    with open(model.path, "wb") as f:
        pickle.dump(rf_model, f)

    # Save scaler
    Path(scaler.path).parent.mkdir(parents=True, exist_ok=True)
    with open(scaler.path, "wb") as f:
        pickle.dump(scaler_obj, f)

    # Log metrics
    metrics.log_metric("train_accuracy", train_score)
    metrics.log_metric("test_accuracy", test_score)
    metrics.log_metric("n_features", X.shape[1])
    metrics.log_metric("n_training_samples", len(X_train))

    # Save model directory info
    model_dir = "/tmp/model_artifacts"
    Path(model_dir).mkdir(parents=True, exist_ok=True)
    model_info = {
        "model_type": "RandomForestClassifier",
        "n_estimators": n_estimators,
        "test_accuracy": test_score,
        "train_accuracy": train_score,
    }
    with open(f"{model_dir}/model_info.json", "w") as f:
        json.dump(model_info, f)

    print(f"Model trained - Test accuracy: {test_score:.4f}")

    # Return the model directory path
    return model_dir


@component(
    base_image="python:3.11-slim",
    packages_to_install=["scikit-learn==1.5.2", "pandas==2.2.3", "numpy==1.26.4"],
)
def evaluate_model(
    model: Input[Model],
    scaler: Input[Artifact],
    accuracy_threshold: float,
    f1_threshold: float,
    evaluation_report: Output[Artifact],
    metrics: Output[Metrics],
) -> str:
    """
    Evaluate trained model and make deployment decision.

    Returns:
        str: "deploy" or "no-deploy" based on thresholds
    """
    import json
    import pickle

    import pandas as pd
    from sklearn.datasets import load_iris
    from sklearn.metrics import accuracy_score, classification_report, f1_score
    from sklearn.model_selection import train_test_split

    print("Evaluating model performance...")

    # Load model and scaler
    with open(model.path, "rb") as f:
        rf_model = pickle.load(f)

    with open(scaler.path, "rb") as f:
        scaler_obj = pickle.load(f)

    # Load test data (same split as training)
    iris = load_iris()
    X = pd.DataFrame(iris.data, columns=iris.feature_names)
    y = pd.Series(iris.target)

    _, X_test, _, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Scale and predict
    X_test_scaled = scaler_obj.transform(X_test)
    y_pred = rf_model.predict(X_test_scaled)

    # Calculate metrics
    accuracy = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, average="weighted")

    # Log metrics
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

    print(f"Evaluation complete - Deploy: {deploy_decision}")
    return deploy_decision


@component(base_image="python:3.11-slim", packages_to_install=["minio==7.2.10"])
def prepare_model_serving(
    model: Input[Model],
    scaler: Input[Artifact],
    model_dir: str,
    serving_uri: OutputPath(str),
) -> None:
    """
    Prepare model for serving with KServe.

    This component packages the model and uploads to storage.
    """
    import os
    import shutil
    from pathlib import Path

    print("Preparing model for serving...")

    # Create serving directory
    serving_path = Path("/tmp/model_serving")
    serving_path.mkdir(parents=True, exist_ok=True)

    # Copy model artifacts
    shutil.copy(model.path, serving_path / "model.pkl")
    shutil.copy(scaler.path, serving_path / "scaler.pkl")

    # Copy model info
    if os.path.exists(f"{model_dir}/model_info.json"):
        shutil.copy(f"{model_dir}/model_info.json", serving_path / "model_info.json")

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
    model: Input[Model], monitoring_config: Output[Artifact]
) -> None:
    """
    Setup drift monitoring configuration.

    Creates baseline data and monitoring configuration.
    """
    import json

    import pandas as pd
    from sklearn.datasets import load_iris
    from sklearn.model_selection import train_test_split

    print("Setting up drift monitoring...")

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
    }

    # Save configuration
    with open(monitoring_config.path, "w") as f:
        json.dump(config, f, indent=2)

    print("Drift monitoring configured")


@component(base_image="python:3.11-slim", packages_to_install=["pydantic==2.11.0"])
def register_model(
    model: Input[Model],
    evaluation_report: Input[Artifact],
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

    print(f"Registering model: {model_name} v{model_version}")

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
        },
        "status": "production-ready",
        "tags": ["iris", "classification", "ml-pipeline"],
    }

    # Save registry entry
    with open(registry_entry.path, "w") as f:
        json.dump(registry_metadata, f, indent=2)

    print("Model registered successfully")


@dsl.pipeline(
    name="Iris Classification Pipeline",
    description="End-to-end ML pipeline with training, evaluation, serving, and monitoring",
)
def iris_ml_pipeline(
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

    This pipeline demonstrates:
    1. Model training with configurable hyperparameters
    2. Model evaluation with deployment gates
    3. Conditional deployment based on performance
    4. Model serving preparation
    5. Drift monitoring setup
    6. Model registry integration
    """

    # Step 1: Train the model
    train_task = train_iris_model(
        n_estimators=n_estimators, test_size=test_size, random_state=random_state
    )
    train_task.set_display_name("Train Iris Model")

    # Step 2: Evaluate the model
    eval_task = evaluate_model(
        model=train_task.outputs["model"],
        scaler=train_task.outputs["scaler"],
        accuracy_threshold=accuracy_threshold,
        f1_threshold=f1_threshold,
    )
    eval_task.set_display_name("Evaluate Model Performance")

    # Step 3: Conditional deployment
    with dsl.If(eval_task.outputs["Output"] == "deploy", name="deployment-gate"):
        # Prepare for serving
        serving_task = prepare_model_serving(
            model=train_task.outputs["model"],
            scaler=train_task.outputs["scaler"],
            model_dir=train_task.outputs["Output"],
        )
        serving_task.set_display_name("Prepare Model Serving")

        # Setup monitoring
        monitoring_task = setup_drift_monitoring(model=train_task.outputs["model"])
        monitoring_task.set_display_name("Setup Drift Monitoring")

        # Register model
        registry_task = register_model(
            model=train_task.outputs["model"],
            evaluation_report=eval_task.outputs["evaluation_report"],
            model_name=model_name,
            model_version=model_version,
        )
        registry_task.set_display_name("Register Model")


def compile_pipeline(output_file: str = "iris_pipeline.yaml"):
    """
    Compile the pipeline to YAML format.

    Args:
        output_file: Output filename for compiled pipeline
    """
    kfp.compiler.Compiler().compile(
        pipeline_func=iris_ml_pipeline, package_path=output_file
    )
    print(f"Pipeline compiled to: {output_file}")


if __name__ == "__main__":
    # Compile the pipeline
    compile_pipeline()
