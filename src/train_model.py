"""
Model training component for Kubeflow pipeline.

This module implements a simple Iris classification model using scikit-learn.
It demonstrates how to:
- Load and preprocess data
- Train a model
- Save model artifacts for deployment
- Log metrics for tracking
"""

import json
import logging
import pickle
from pathlib import Path

import pandas as pd
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_and_prepare_data() -> tuple[pd.DataFrame, pd.Series]:
    """
    Load the Iris dataset and prepare it for training.

    Returns:
        Tuple[pd.DataFrame, pd.Series]: Features (X) and labels (y)

    Notes:
        - Uses the built-in Iris dataset from scikit-learn
        - This is a classification problem with 3 classes
        - Features: sepal length/width, petal length/width
    """
    logger.info("Loading Iris dataset...")
    iris = load_iris()

    # Create DataFrame for better handling
    X = pd.DataFrame(iris.data, columns=iris.feature_names)
    y = pd.Series(iris.target, name="species")

    logger.info(f"Dataset loaded: {X.shape[0]} samples, {X.shape[1]} features")
    logger.info(f"Classes: {iris.target_names.tolist()}")

    return X, y


def train_model(
    X_train: pd.DataFrame,
    y_train: pd.Series,
    n_estimators: int = 100,
    random_state: int = 42,
) -> RandomForestClassifier:
    """
    Train a Random Forest classifier on the provided data.

    Args:
        X_train: Training features
        y_train: Training labels
        n_estimators: Number of trees in the forest
        random_state: Random seed for reproducibility

    Returns:
        RandomForestClassifier: Trained model

    Notes:
        - Random Forest is chosen for its robustness and interpretability
        - No hyperparameter tuning in this simple example
    """
    logger.info(f"Training Random Forest with {n_estimators} estimators...")

    model = RandomForestClassifier(
        n_estimators=n_estimators,
        random_state=random_state,
        n_jobs=-1,  # Use all CPU cores
    )

    model.fit(X_train, y_train)
    logger.info("Model training completed")

    return model


def save_artifacts(
    model: RandomForestClassifier,
    scaler: StandardScaler,
    metrics: dict[str, float],
    output_dir: str = "models",
) -> None:
    """
    Save model artifacts and metadata for later use.

    Args:
        model: Trained model
        scaler: Fitted scaler
        metrics: Model performance metrics
        output_dir: Directory to save artifacts

    Notes:
        - Saves model as pickle file
        - Saves scaler for preprocessing new data
        - Saves metrics as JSON for tracking
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Save model
    model_path = output_path / "model.pkl"
    with open(model_path, "wb") as f:
        pickle.dump(model, f)
    logger.info(f"Model saved to {model_path}")

    # Save scaler
    scaler_path = output_path / "scaler.pkl"
    with open(scaler_path, "wb") as f:
        pickle.dump(scaler, f)
    logger.info(f"Scaler saved to {scaler_path}")

    # Save metrics
    metrics_path = output_path / "metrics.json"
    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)
    logger.info(f"Metrics saved to {metrics_path}")

    # Save model info
    model_info = {
        "model_type": "RandomForestClassifier",
        "n_estimators": model.n_estimators,
        "n_features": model.n_features_in_,
        "feature_names": model.feature_names_in_.tolist()
        if hasattr(model, "feature_names_in_")
        else None,
        "classes": model.classes_.tolist(),
    }
    info_path = output_path / "model_info.json"
    with open(info_path, "w") as f:
        json.dump(model_info, f, indent=2)
    logger.info(f"Model info saved to {info_path}")


def main(
    test_size: float = 0.2,
    n_estimators: int = 100,
    random_state: int = 42,
    output_dir: str = "models",
) -> dict[str, float]:
    """
    Main training pipeline function.

    Args:
        test_size: Proportion of data to use for testing
        n_estimators: Number of trees in Random Forest
        random_state: Random seed for reproducibility
        output_dir: Directory to save model artifacts

    Returns:
        Dict[str, float]: Training metrics

    Notes:
        - This function orchestrates the entire training process
        - Can be called directly or wrapped as a Kubeflow component
    """
    logger.info("Starting model training pipeline...")

    # Load data
    X, y = load_and_prepare_data()

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )
    logger.info(f"Data split: {len(X_train)} train, {len(X_test)} test samples")

    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # Convert back to DataFrame to preserve feature names
    X_train_scaled = pd.DataFrame(X_train_scaled, columns=X.columns)
    X_test_scaled = pd.DataFrame(X_test_scaled, columns=X.columns)

    # Train model
    model = train_model(X_train_scaled, y_train, n_estimators, random_state)

    # Evaluate model
    train_score = model.score(X_train_scaled, y_train)
    test_score = model.score(X_test_scaled, y_test)

    metrics = {
        "train_accuracy": float(train_score),
        "test_accuracy": float(test_score),
        "n_train_samples": len(X_train),
        "n_test_samples": len(X_test),
        "n_features": X.shape[1],
        "n_classes": len(y.unique()),
    }

    logger.info(f"Training accuracy: {train_score:.4f}")
    logger.info(f"Test accuracy: {test_score:.4f}")

    # Save artifacts
    save_artifacts(model, scaler, metrics, output_dir)

    logger.info("Training pipeline completed successfully")
    return metrics


if __name__ == "__main__":
    # Run training when script is executed directly
    metrics = main()
    print(f"Training completed. Metrics: {metrics}")
