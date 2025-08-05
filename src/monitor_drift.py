"""
Data and model drift monitoring component.

This module implements drift detection using Evidently library:
- Data drift detection
- Model performance monitoring
- Feature distribution analysis
- Automated alerting based on drift metrics
"""

import json
import logging
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
from evidently.metrics import (
    DataDriftTable,
    DatasetDriftMetric,
    DatasetMissingValuesMetric,
    DatasetSummaryMetric,
)
from evidently.pipeline.column_mapping import ColumnMapping
from evidently.report import Report
from evidently.test_preset import DataDriftTestPreset
from evidently.test_suite import TestSuite
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DriftMonitor:
    """
    Monitor data and model drift over time.

    This class provides comprehensive drift detection capabilities
    for production ML models.
    """

    def __init__(
        self,
        reference_data: pd.DataFrame,
        model_path: str = "models",
        drift_threshold: float = 0.5,
    ):
        """
        Initialize drift monitor with reference data.

        Args:
            reference_data: Baseline data for comparison
            model_path: Path to model artifacts
            drift_threshold: Threshold for drift detection (0-1)
        """
        self.reference_data = reference_data
        self.model_path = Path(model_path)
        self.drift_threshold = drift_threshold

        # Define column mapping for Iris dataset
        self.column_mapping = ColumnMapping(
            target="species",
            prediction="prediction",
            numerical_features=[
                "sepal length (cm)",
                "sepal width (cm)",
                "petal length (cm)",
                "petal width (cm)",
            ],
        )

        logger.info(
            f"Drift monitor initialized with {len(reference_data)} reference samples"
        )

    def detect_data_drift(
        self, current_data: pd.DataFrame, save_report: bool = True
    ) -> dict[str, any]:
        """
        Detect data drift between reference and current data.

        Args:
            current_data: New data to compare against reference
            save_report: Whether to save HTML report

        Returns:
            Dict containing drift metrics and results
        """
        logger.info("Detecting data drift...")

        # Create drift report
        data_drift_report = Report(
            metrics=[
                DatasetDriftMetric(),
                DataDriftTable(),
                DatasetSummaryMetric(),
                DatasetMissingValuesMetric(),
            ]
        )

        # Run the report
        data_drift_report.run(
            reference_data=self.reference_data,
            current_data=current_data,
            column_mapping=self.column_mapping,
        )

        # Extract results
        report_dict = data_drift_report.as_dict()

        # Parse drift results
        drift_detected = report_dict["metrics"][0]["result"]["dataset_drift"]
        drift_score = report_dict["metrics"][0]["result"]["drift_score"]

        # Feature-level drift
        feature_drift = {}
        drift_table = report_dict["metrics"][1]["result"]["drift_by_columns"]

        for column, details in drift_table.items():
            if column != "species":  # Skip target column
                feature_drift[column] = {
                    "drift_detected": details["drift_detected"],
                    "drift_score": details["drift_score"],
                    "stattest_name": details["stattest_name"],
                    "threshold": details["threshold"],
                }

        # Prepare results
        drift_results = {
            "dataset_drift_detected": drift_detected,
            "dataset_drift_score": drift_score,
            "feature_drift": feature_drift,
            "n_features_drifted": sum(
                1 for f in feature_drift.values() if f["drift_detected"]
            ),
            "timestamp": datetime.now().isoformat(),
        }

        # Save report if requested
        if save_report:
            report_path = (
                self.model_path
                / f"drift_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
            )
            data_drift_report.save_html(str(report_path))
            logger.info(f"Drift report saved to {report_path}")

        logger.info(f"Data drift detected: {drift_detected} (score: {drift_score:.3f})")

        return drift_results

    def run_drift_tests(self, current_data: pd.DataFrame) -> dict[str, any]:
        """
        Run comprehensive drift tests.

        Args:
            current_data: New data to test

        Returns:
            Dict containing test results
        """
        logger.info("Running drift test suite...")

        # Create test suite
        drift_tests = TestSuite(tests=[DataDriftTestPreset()])

        # Run tests
        drift_tests.run(
            reference_data=self.reference_data,
            current_data=current_data,
            column_mapping=self.column_mapping,
        )

        # Extract results
        test_results = drift_tests.as_dict()

        # Parse test results
        tests_summary = {
            "total_tests": test_results["summary"]["total_tests"],
            "passed_tests": test_results["summary"]["success_tests"],
            "failed_tests": test_results["summary"]["failed_tests"],
            "success_rate": (
                test_results["summary"]["success_tests"]
                / test_results["summary"]["total_tests"]
            ),
            "test_details": [],
        }

        # Extract individual test results
        for test in test_results["tests"]:
            tests_summary["test_details"].append(
                {
                    "name": test["name"],
                    "status": test["status"],
                    "description": test["description"],
                }
            )

        logger.info(
            f"Tests completed: {tests_summary['passed_tests']}/{tests_summary['total_tests']} passed"
        )

        return tests_summary

    def monitor_prediction_drift(
        self,
        current_predictions: pd.DataFrame,
        reference_predictions: pd.DataFrame | None = None,
    ) -> dict[str, any]:
        """
        Monitor drift in model predictions.

        Args:
            current_predictions: Recent model predictions
            reference_predictions: Baseline predictions (optional)

        Returns:
            Dict containing prediction drift metrics
        """
        logger.info("Monitoring prediction drift...")

        # If no reference predictions provided, use uniform distribution
        if reference_predictions is None:
            # Assume balanced classes for Iris
            n_samples = len(self.reference_data)
            reference_predictions = pd.DataFrame(
                {"prediction": np.random.choice([0, 1, 2], size=n_samples)}
            )

        # Calculate prediction distributions
        current_dist = (
            current_predictions["prediction"].value_counts(normalize=True).sort_index()
        )
        reference_dist = (
            reference_predictions["prediction"]
            .value_counts(normalize=True)
            .sort_index()
        )

        # Calculate KL divergence
        kl_divergence = 0
        for i in range(3):  # 3 classes
            p = reference_dist.get(i, 1e-10)
            q = current_dist.get(i, 1e-10)
            kl_divergence += p * np.log(p / q)

        # Chi-square test
        from scipy.stats import chisquare

        chi2_stat, p_value = chisquare(current_dist.values, reference_dist.values)

        prediction_drift = {
            "kl_divergence": float(kl_divergence),
            "chi2_statistic": float(chi2_stat),
            "p_value": float(p_value),
            "drift_detected": p_value < 0.05,
            "current_distribution": current_dist.to_dict(),
            "reference_distribution": reference_dist.to_dict(),
        }

        logger.info(
            f"Prediction drift - KL: {kl_divergence:.3f}, p-value: {p_value:.3f}"
        )

        return prediction_drift

    def generate_monitoring_summary(
        self,
        data_drift_results: dict[str, any],
        test_results: dict[str, any],
        prediction_drift: dict[str, any] | None = None,
    ) -> dict[str, any]:
        """
        Generate comprehensive monitoring summary.

        Args:
            data_drift_results: Data drift detection results
            test_results: Drift test suite results
            prediction_drift: Prediction drift results (optional)

        Returns:
            Dict containing monitoring summary and recommendations
        """
        # Overall drift status
        drift_severity = "none"
        if data_drift_results["dataset_drift_detected"]:
            if data_drift_results["dataset_drift_score"] > 0.7:
                drift_severity = "high"
            elif data_drift_results["dataset_drift_score"] > 0.5:
                drift_severity = "medium"
            else:
                drift_severity = "low"

        # Recommendations
        recommendations = []
        if drift_severity in ["medium", "high"]:
            recommendations.append("Consider retraining the model with recent data")

        if data_drift_results["n_features_drifted"] > 2:
            recommendations.append(
                "Multiple features showing drift - investigate data pipeline"
            )

        if test_results["success_rate"] < 0.8:
            recommendations.append("Drift tests failing - immediate attention required")

        if prediction_drift and prediction_drift["drift_detected"]:
            recommendations.append(
                "Prediction distribution shifted - monitor model performance"
            )

        # Generate summary
        summary = {
            "monitoring_timestamp": datetime.now().isoformat(),
            "overall_status": "alert" if drift_severity in ["medium", "high"] else "ok",
            "drift_severity": drift_severity,
            "data_drift": {
                "detected": data_drift_results["dataset_drift_detected"],
                "score": data_drift_results["dataset_drift_score"],
                "features_affected": data_drift_results["n_features_drifted"],
            },
            "test_summary": {
                "total_tests": test_results["total_tests"],
                "passed": test_results["passed_tests"],
                "success_rate": test_results["success_rate"],
            },
            "recommendations": recommendations,
            "next_check": "Monitor daily for the next week",
        }

        if prediction_drift:
            summary["prediction_drift"] = {
                "detected": prediction_drift["drift_detected"],
                "kl_divergence": prediction_drift["kl_divergence"],
            }

        return summary


def simulate_drift_scenario() -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Simulate a drift scenario for testing.

    Returns:
        Tuple of (reference_data, drifted_data)
    """
    # Load Iris data
    iris = load_iris()
    X = pd.DataFrame(iris.data, columns=iris.feature_names)
    y = pd.Series(iris.target, name="species")

    # Create reference and current datasets
    X_ref, X_curr, y_ref, y_curr = train_test_split(
        X, y, test_size=0.5, random_state=42
    )

    # Add labels to dataframes
    reference_data = X_ref.copy()
    reference_data["species"] = y_ref

    current_data = X_curr.copy()
    current_data["species"] = y_curr

    # Introduce drift in current data
    # Shift some features to simulate drift
    drift_factor = 0.2
    current_data["sepal length (cm)"] += np.random.normal(
        drift_factor, 0.1, size=len(current_data)
    )
    current_data["petal width (cm)"] *= 1 + drift_factor

    return reference_data, current_data


def main(
    reference_data_path: str | None = None,
    current_data_path: str | None = None,
    model_path: str = "models",
    save_reports: bool = True,
) -> dict[str, any]:
    """
    Main drift monitoring pipeline.

    Args:
        reference_data_path: Path to reference dataset
        current_data_path: Path to current dataset
        model_path: Path to model artifacts
        save_reports: Whether to save HTML reports

    Returns:
        Dict containing all monitoring results
    """
    logger.info("Starting drift monitoring pipeline...")

    # Load or simulate data
    if reference_data_path and current_data_path:
        reference_data = pd.read_csv(reference_data_path)
        current_data = pd.read_csv(current_data_path)
    else:
        # Use simulated drift scenario for demo
        logger.info("Using simulated drift scenario for demonstration")
        reference_data, current_data = simulate_drift_scenario()

    # Initialize monitor
    monitor = DriftMonitor(reference_data, model_path)

    # Run drift detection
    data_drift_results = monitor.detect_data_drift(current_data, save_reports)

    # Run drift tests
    test_results = monitor.run_drift_tests(current_data)

    # Generate monitoring summary
    monitoring_summary = monitor.generate_monitoring_summary(
        data_drift_results, test_results
    )

    # Save monitoring results
    output_path = Path(model_path) / "monitoring"
    output_path.mkdir(exist_ok=True)

    results_file = (
        output_path
        / f"monitoring_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    )
    with open(results_file, "w") as f:
        json.dump(
            {
                "data_drift": data_drift_results,
                "test_results": test_results,
                "summary": monitoring_summary,
            },
            f,
            indent=2,
        )

    logger.info(f"Monitoring results saved to {results_file}")
    logger.info(f"Overall status: {monitoring_summary['overall_status']}")

    return monitoring_summary


if __name__ == "__main__":
    # Run monitoring when script is executed directly
    results = main()
    print(f"Monitoring completed. Status: {results['overall_status']}")
