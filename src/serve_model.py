"""
Model serving component using FastAPI.

This module implements a REST API for model inference with:
- Input validation using Pydantic
- Prediction endpoints
- Model metadata endpoints
- Health checks
- Integration ready for KServe
"""

import json
import logging
import pickle
from datetime import datetime
from pathlib import Path

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, validator

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Iris Model Serving API",
    description="REST API for Iris classification model serving",
    version="1.0.0",
)

# Global variables for model artifacts
MODEL = None
SCALER = None
MODEL_INFO = None
CLASS_NAMES = ["setosa", "versicolor", "virginica"]


class IrisFeatures(BaseModel):
    """
    Input schema for Iris prediction.

    Validates input features for the Iris classification model.
    """

    sepal_length: float = Field(..., gt=0, description="Sepal length in cm")
    sepal_width: float = Field(..., gt=0, description="Sepal width in cm")
    petal_length: float = Field(..., gt=0, description="Petal length in cm")
    petal_width: float = Field(..., gt=0, description="Petal width in cm")

    @validator("*")
    def validate_positive(cls, v, field):
        """Ensure all measurements are positive."""
        if v <= 0:
            raise ValueError(f"{field.name} must be positive")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "sepal_length": 5.1,
                "sepal_width": 3.5,
                "petal_length": 1.4,
                "petal_width": 0.2,
            }
        }


class BatchPredictionRequest(BaseModel):
    """Schema for batch prediction requests."""

    instances: list[IrisFeatures] = Field(
        ..., description="List of instances to predict"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "instances": [
                    {
                        "sepal_length": 5.1,
                        "sepal_width": 3.5,
                        "petal_length": 1.4,
                        "petal_width": 0.2,
                    },
                    {
                        "sepal_length": 6.2,
                        "sepal_width": 2.9,
                        "petal_length": 4.3,
                        "petal_width": 1.3,
                    },
                ]
            }
        }


class PredictionResponse(BaseModel):
    """Schema for prediction response."""

    prediction: str = Field(..., description="Predicted class name")
    prediction_id: int = Field(..., description="Predicted class ID")
    confidence: float = Field(..., description="Prediction confidence score")
    probabilities: dict[str, float] = Field(..., description="Class probabilities")
    timestamp: str = Field(..., description="Prediction timestamp")


class BatchPredictionResponse(BaseModel):
    """Schema for batch prediction response."""

    predictions: list[PredictionResponse]
    batch_size: int
    processing_time_ms: float


class ModelInfo(BaseModel):
    """Schema for model information."""

    model_type: str
    version: str
    n_features: int
    feature_names: list[str]
    classes: list[str]
    training_accuracy: float | None
    loaded_at: str


def load_model_artifacts(model_dir: str = "models") -> None:
    """
    Load model artifacts from disk.

    Args:
        model_dir: Directory containing model artifacts

    Raises:
        RuntimeError: If model loading fails
    """
    global MODEL, SCALER, MODEL_INFO

    try:
        model_path = Path(model_dir)

        # Load model
        with open(model_path / "model.pkl", "rb") as f:
            MODEL = pickle.load(f)
        logger.info("Model loaded successfully")

        # Load scaler
        with open(model_path / "scaler.pkl", "rb") as f:
            SCALER = pickle.load(f)
        logger.info("Scaler loaded successfully")

        # Load model info
        with open(model_path / "model_info.json") as f:
            MODEL_INFO = json.load(f)
        MODEL_INFO["loaded_at"] = datetime.now().isoformat()
        logger.info("Model info loaded successfully")

    except Exception as e:
        logger.error(f"Failed to load model artifacts: {e}")
        raise RuntimeError(f"Model loading failed: {e}")


@app.on_event("startup")
async def startup_event():
    """Load model artifacts on API startup."""
    logger.info("Starting model serving API...")
    load_model_artifacts()
    logger.info("Model serving API ready")


@app.get("/", tags=["General"])
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Iris Model Serving API",
        "version": "1.0.0",
        "description": "REST API for Iris classification",
        "endpoints": {
            "health": "/health",
            "model_info": "/model/info",
            "predict": "/predict",
            "batch_predict": "/predict/batch",
        },
    }


@app.get("/health", tags=["Health"])
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "model_loaded": MODEL is not None,
        "timestamp": datetime.now().isoformat(),
    }


@app.get("/model/info", response_model=ModelInfo, tags=["Model"])
async def get_model_info():
    """Get information about the loaded model."""
    if MODEL is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    # Get training metrics if available
    training_accuracy = None
    try:
        with open("models/metrics.json") as f:
            metrics = json.load(f)
            training_accuracy = metrics.get("test_accuracy")
    except Exception:
        pass

    return ModelInfo(
        model_type=MODEL_INFO.get("model_type", "Unknown"),
        version="1.0.0",
        n_features=MODEL_INFO.get("n_features", 4),
        feature_names=MODEL_INFO.get(
            "feature_names",
            [
                "sepal length (cm)",
                "sepal width (cm)",
                "petal length (cm)",
                "petal width (cm)",
            ],
        ),
        classes=MODEL_INFO.get("classes", CLASS_NAMES),
        training_accuracy=training_accuracy,
        loaded_at=MODEL_INFO.get("loaded_at", datetime.now().isoformat()),
    )


@app.post("/predict", response_model=PredictionResponse, tags=["Prediction"])
async def predict(features: IrisFeatures):
    """
    Make a single prediction.

    Args:
        features: Input features for prediction

    Returns:
        PredictionResponse with prediction details
    """
    if MODEL is None or SCALER is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        # Prepare input data
        input_data = np.array(
            [
                [
                    features.sepal_length,
                    features.sepal_width,
                    features.petal_length,
                    features.petal_width,
                ]
            ]
        )

        # Scale features
        input_scaled = SCALER.transform(input_data)

        # Make prediction
        prediction = MODEL.predict(input_scaled)[0]
        probabilities = MODEL.predict_proba(input_scaled)[0]

        # Prepare response
        prob_dict = {
            CLASS_NAMES[i]: float(prob) for i, prob in enumerate(probabilities)
        }

        return PredictionResponse(
            prediction=CLASS_NAMES[prediction],
            prediction_id=int(prediction),
            confidence=float(max(probabilities)),
            probabilities=prob_dict,
            timestamp=datetime.now().isoformat(),
        )

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


@app.post("/predict/batch", response_model=BatchPredictionResponse, tags=["Prediction"])
async def predict_batch(request: BatchPredictionRequest):
    """
    Make batch predictions.

    Args:
        request: Batch prediction request with multiple instances

    Returns:
        BatchPredictionResponse with all predictions
    """
    if MODEL is None or SCALER is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    start_time = datetime.now()
    predictions = []

    try:
        # Process each instance
        for instance in request.instances:
            # Prepare input data
            input_data = np.array(
                [
                    [
                        instance.sepal_length,
                        instance.sepal_width,
                        instance.petal_length,
                        instance.petal_width,
                    ]
                ]
            )

            # Scale features
            input_scaled = SCALER.transform(input_data)

            # Make prediction
            prediction = MODEL.predict(input_scaled)[0]
            probabilities = MODEL.predict_proba(input_scaled)[0]

            # Prepare response
            prob_dict = {
                CLASS_NAMES[i]: float(prob) for i, prob in enumerate(probabilities)
            }

            predictions.append(
                PredictionResponse(
                    prediction=CLASS_NAMES[prediction],
                    prediction_id=int(prediction),
                    confidence=float(max(probabilities)),
                    probabilities=prob_dict,
                    timestamp=datetime.now().isoformat(),
                )
            )

        # Calculate processing time
        processing_time = (datetime.now() - start_time).total_seconds() * 1000

        return BatchPredictionResponse(
            predictions=predictions,
            batch_size=len(predictions),
            processing_time_ms=processing_time,
        )

    except Exception as e:
        logger.error(f"Batch prediction error: {e}")
        raise HTTPException(
            status_code=500, detail=f"Batch prediction failed: {str(e)}"
        )


# KServe V2 Protocol endpoints for compatibility
@app.get("/v2/health/ready", tags=["KServe"])
async def kserve_ready():
    """KServe readiness check."""
    return {"ready": MODEL is not None}


@app.get("/v2/health/live", tags=["KServe"])
async def kserve_live():
    """KServe liveness check."""
    return {"live": True}


@app.get("/v2/models/{model_name}", tags=["KServe"])
async def kserve_model_metadata(model_name: str):
    """KServe model metadata endpoint."""
    return {
        "name": model_name,
        "platform": "sklearn",
        "inputs": [{"name": "input", "datatype": "FP32", "shape": [-1, 4]}],
        "outputs": [{"name": "output", "datatype": "INT64", "shape": [-1]}],
    }


if __name__ == "__main__":
    import uvicorn

    # Run the FastAPI app
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
