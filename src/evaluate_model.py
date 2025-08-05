"""
Model evaluation component for Kubeflow pipeline.

This module implements comprehensive model evaluation including:
- Performance metrics calculation
- Confusion matrix generation
- Feature importance analysis
- Model validation checks
"""

import json
import logging
import pickle
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import cross_val_score

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_model_artifacts(model_dir: str) -> tuple:
    """
    Load trained model and associated artifacts.

    Args:
        model_dir: Directory containing model artifacts

    Returns:
        Tuple containing model, scaler, and metrics

    Raises:
        FileNotFoundError: If required artifacts are missing
    """
    model_path = Path(model_dir)

    # Load model
    with open(model_path / "model.pkl", "rb") as f:
        model = pickle.load(f)
    logger.info("Model loaded successfully")

    # Load scaler
    with open(model_path / "scaler.pkl", "rb") as f:
        scaler = pickle.load(f)
    logger.info("Scaler loaded successfully")

    # Load training metrics
    with open(model_path / "metrics.json") as f:
        train_metrics = json.load(f)
    logger.info("Training metrics loaded successfully")

    return model, scaler, train_metrics


def evaluate_model_performance(
    model, X_test: pd.DataFrame, y_test: pd.Series, class_names: list | None = None
) -> dict[str, any]:
    """
    Perform comprehensive model evaluation.

    Args:
        model: Trained model
        X_test: Test features
        y_test: True labels
        class_names: Names of target classes

    Returns:
        Dict containing evaluation metrics and results

    Notes:
        - Calculates multiple classification metrics
        - Generates confusion matrix
        - Produces classification report
    """
    logger.info("Evaluating model performance...")

    # Make predictions
    y_pred = model.predict(X_test)
    y_pred_proba = model.predict_proba(X_test)

    # Calculate metrics
    accuracy = accuracy_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred, average="weighted")
    recall = recall_score(y_test, y_pred, average="weighted")
    f1 = f1_score(y_test, y_pred, average="weighted")

    # Confusion matrix
    cm = confusion_matrix(y_test, y_pred)

    # Classification report
    report = classification_report(
        y_test, y_pred, target_names=class_names, output_dict=True
    )

    # Feature importance (for tree-based models)
    feature_importance = None
    if hasattr(model, "feature_importances_"):
        feature_importance = {
            feature: float(importance)
            for feature, importance in zip(X_test.columns, model.feature_importances_)
        }

    evaluation_results = {
        "accuracy": float(accuracy),
        "precision": float(precision),
        "recall": float(recall),
        "f1_score": float(f1),
        "confusion_matrix": cm.tolist(),
        "classification_report": report,
        "feature_importance": feature_importance,
        "prediction_confidence": {
            "mean": float(np.mean(np.max(y_pred_proba, axis=1))),
            "std": float(np.std(np.max(y_pred_proba, axis=1))),
            "min": float(np.min(np.max(y_pred_proba, axis=1))),
            "max": float(np.max(np.max(y_pred_proba, axis=1))),
        },
    }

    logger.info(f"Evaluation completed - Accuracy: {accuracy:.4f}, F1: {f1:.4f}")

    return evaluation_results


def perform_cross_validation(
    model, X: pd.DataFrame, y: pd.Series, cv_folds: int = 5
) -> dict[str, float]:
    """
    Perform cross-validation to assess model stability.

    Args:
        model: Trained model
        X: Features
        y: Labels
        cv_folds: Number of cross-validation folds

    Returns:
        Dict containing cross-validation results

    Notes:
        - Uses stratified k-fold for balanced evaluation
        - Provides insight into model variance
    """
    logger.info(f"Performing {cv_folds}-fold cross-validation...")

    cv_scores = cross_val_score(model, X, y, cv=cv_folds, scoring="accuracy")

    cv_results = {
        "cv_scores": cv_scores.tolist(),
        "cv_mean": float(cv_scores.mean()),
        "cv_std": float(cv_scores.std()),
        "cv_min": float(cv_scores.min()),
        "cv_max": float(cv_scores.max()),
    }

    logger.info(
        f"CV Score: {cv_results['cv_mean']:.4f} (+/- {cv_results['cv_std']:.4f})"
    )

    return cv_results


def check_model_thresholds(
    evaluation_results: dict[str, any],
    accuracy_threshold: float = 0.8,
    f1_threshold: float = 0.8,
) -> dict[str, bool]:
    """
    Check if model meets deployment thresholds.

    Args:
        evaluation_results: Model evaluation metrics
        accuracy_threshold: Minimum acceptable accuracy
        f1_threshold: Minimum acceptable F1 score

    Returns:
        Dict indicating which thresholds are met

    Notes:
        - Used to gate model deployment
        - Can be customized based on business requirements
    """
    checks = {
        "accuracy_check": evaluation_results["accuracy"] >= accuracy_threshold,
        "f1_check": evaluation_results["f1_score"] >= f1_threshold,
        "accuracy_value": evaluation_results["accuracy"],
        "f1_value": evaluation_results["f1_score"],
        "accuracy_threshold": accuracy_threshold,
        "f1_threshold": f1_threshold,
        "all_checks_passed": True,
    }

    # Overall check
    checks["all_checks_passed"] = all([checks["accuracy_check"], checks["f1_check"]])

    logger.info(
        f"Threshold checks - Accuracy: {checks['accuracy_check']}, F1: {checks['f1_check']}"
    )

    return checks


def save_evaluation_results(
    evaluation_results: dict[str, any],
    cv_results: dict[str, float],
    threshold_checks: dict[str, bool],
    output_dir: str = "models",
) -> None:
    """
    Save evaluation results and reports.

    Args:
        evaluation_results: Model evaluation metrics
        cv_results: Cross-validation results
        threshold_checks: Deployment threshold checks
        output_dir: Directory to save results
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Combine all results
    full_evaluation = {
        "evaluation_metrics": evaluation_results,
        "cross_validation": cv_results,
        "threshold_checks": threshold_checks,
        "evaluation_timestamp": pd.Timestamp.now().isoformat(),
    }

    # Save evaluation report
    eval_path = output_path / "evaluation_report.json"
    with open(eval_path, "w") as f:
        json.dump(full_evaluation, f, indent=2)

    logger.info(f"Evaluation report saved to {eval_path}")


def main(
    model_dir: str = "models",
    test_data_path: str | None = None,
    accuracy_threshold: float = 0.8,
    f1_threshold: float = 0.8,
    cv_folds: int = 5,
) -> dict[str, any]:
    """
    Main evaluation pipeline function.

    Args:
        model_dir: Directory containing model artifacts
        test_data_path: Path to test data (if separate from training)
        accuracy_threshold: Minimum acceptable accuracy
        f1_threshold: Minimum acceptable F1 score
        cv_folds: Number of cross-validation folds

    Returns:
        Dict containing all evaluation results

    Notes:
        - Can be called directly or wrapped as Kubeflow component
        - Returns deployment decision based on thresholds
    """
    logger.info("Starting model evaluation pipeline...")

    # Load model artifacts
    model, scaler, train_metrics = load_model_artifacts(model_dir)

    # For demo, we'll re-load and split the Iris data
    # In production, this would load from test_data_path
    from sklearn.datasets import load_iris
    from sklearn.model_selection import train_test_split

    iris = load_iris()
    X = pd.DataFrame(iris.data, columns=iris.feature_names)
    y = pd.Series(iris.target)

    # Use same split as training for consistency
    _, X_test, _, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Scale test data
    X_test_scaled = scaler.transform(X_test)
    X_test_scaled = pd.DataFrame(X_test_scaled, columns=X.columns)

    # Evaluate model
    evaluation_results = evaluate_model_performance(
        model, X_test_scaled, y_test, class_names=iris.target_names.tolist()
    )

    # Cross-validation on full scaled dataset
    X_scaled = scaler.transform(X)
    X_scaled = pd.DataFrame(X_scaled, columns=X.columns)
    cv_results = perform_cross_validation(model, X_scaled, y, cv_folds)

    # Check deployment thresholds
    threshold_checks = check_model_thresholds(
        evaluation_results, accuracy_threshold, f1_threshold
    )

    # Save results
    save_evaluation_results(evaluation_results, cv_results, threshold_checks, model_dir)

    # Prepare final output
    final_results = {
        "deploy_model": threshold_checks["all_checks_passed"],
        "evaluation_metrics": evaluation_results,
        "cross_validation": cv_results,
        "threshold_checks": threshold_checks,
    }

    logger.info(f"Evaluation completed. Deploy model: {final_results['deploy_model']}")

    return final_results


if __name__ == "__main__":
    # Run evaluation when script is executed directly
    results = main()
    print(f"Evaluation completed. Deploy: {results['deploy_model']}")
