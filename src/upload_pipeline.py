#!/usr/bin/env python3
"""
Script to properly upload the iris pipeline to Kubeflow
"""

import logging

import kfp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def upload_iris_pipeline():
    """Upload the iris pipeline to Kubeflow."""

    # Create client
    client = kfp.Client(host="http://localhost:8080")

    pipeline_file = "iris_pipeline.yaml"
    pipeline_name = "iris-classification-pipeline"  # Use consistent naming

    # First check if pipeline already exists
    try:
        pipelines = client.list_pipelines()
        for p in pipelines.pipelines:
            if p.display_name == pipeline_name:
                logger.info("✅ Pipeline already exists!")
                logger.info(f"Pipeline ID: {p.pipeline_id}")
                logger.info(
                    f"View at: http://localhost:8080/#/pipelines/details/{p.pipeline_id}"
                )
                return
    except Exception as e:
        logger.warning(f"Error checking existing pipelines: {e}")

    try:
        # Upload new pipeline
        pipeline = client.upload_pipeline(
            pipeline_package_path=pipeline_file,
            pipeline_name=pipeline_name,
            description="End-to-end ML pipeline with training, evaluation, serving, and monitoring",
        )
        logger.info("✅ Pipeline uploaded successfully!")
        logger.info(f"Pipeline ID: {pipeline.pipeline_id}")
        logger.info(
            f"View at: http://localhost:8080/#/pipelines/details/{pipeline.pipeline_id}"
        )

    except Exception as e:
        logger.error(f"Failed to upload pipeline: {e}")
        raise


if __name__ == "__main__":
    upload_iris_pipeline()
