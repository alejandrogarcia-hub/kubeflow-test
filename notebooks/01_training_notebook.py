"""
Training Notebook - Iris Classification Model

This notebook demonstrates the training process for the Iris classification model.
It will be converted to a Jupyter notebook for interactive development.
"""

# %% [markdown]
# # Iris Classification Model Training
#
# This notebook demonstrates how to train a machine learning model for Iris classification
# using scikit-learn. The model will be integrated into a Kubeflow pipeline.
#
# ## Overview
#
# 1. Load and explore the Iris dataset
# 2. Preprocess the data
# 3. Train a Random Forest classifier
# 4. Evaluate model performance
# 5. Save model artifacts for deployment

# %% [markdown]
# ## 1. Setup and Imports

# %%
import json
import pickle
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import cross_val_score, train_test_split
from sklearn.preprocessing import StandardScaler

# Set random seed for reproducibility
np.random.seed(42)

# Configure visualization
plt.style.use("seaborn-v0_8-darkgrid")
sns.set_palette("husl")

# %% [markdown]
# ## 2. Load and Explore the Dataset

# %%
# Load the Iris dataset
iris = load_iris()
X = pd.DataFrame(iris.data, columns=iris.feature_names)
y = pd.Series(iris.target, name="species")

# Create a full dataframe for exploration
df = X.copy()
df["species"] = y
df["species_name"] = df["species"].map(dict(enumerate(iris.target_names)))

print("Dataset shape:", df.shape)
print("\nFirst few rows:")
df.head()

# %%
# Dataset statistics
print("Dataset Statistics:")
print(df.describe())

print("\nClass distribution:")
print(df["species_name"].value_counts())

# %%
# Visualize feature distributions
fig, axes = plt.subplots(2, 2, figsize=(12, 10))
axes = axes.ravel()

for idx, col in enumerate(X.columns):
    axes[idx].hist(df[col], bins=20, edgecolor="black")
    axes[idx].set_title(f"Distribution of {col}")
    axes[idx].set_xlabel(col)
    axes[idx].set_ylabel("Frequency")

plt.tight_layout()
plt.show()

# %%
# Pairplot to visualize relationships
plt.figure(figsize=(12, 10))
sns.pairplot(df, hue="species_name", diag_kind="kde")
plt.suptitle("Iris Features Pairplot", y=1.02)
plt.show()

# %% [markdown]
# ## 3. Data Preprocessing

# %%
# Split the data
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

print(f"Training set size: {len(X_train)}")
print(f"Test set size: {len(X_test)}")
print("\nClass distribution in training set:")
print(y_train.value_counts().sort_index())

# %%
# Feature scaling
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Convert back to DataFrame for better handling
X_train_scaled = pd.DataFrame(X_train_scaled, columns=X.columns, index=X_train.index)
X_test_scaled = pd.DataFrame(X_test_scaled, columns=X.columns, index=X_test.index)

print("Scaled features - mean should be ~0, std should be ~1:")
print(X_train_scaled.describe().round(3))

# %% [markdown]
# ## 4. Model Training

# %%
# Train Random Forest model
rf_model = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)

# Train the model
rf_model.fit(X_train_scaled, y_train)

# Make predictions
y_pred_train = rf_model.predict(X_train_scaled)
y_pred_test = rf_model.predict(X_test_scaled)

# Calculate accuracies
train_accuracy = accuracy_score(y_train, y_pred_train)
test_accuracy = accuracy_score(y_test, y_pred_test)

print(f"Training Accuracy: {train_accuracy:.4f}")
print(f"Test Accuracy: {test_accuracy:.4f}")

# %%
# Detailed classification report
print("Classification Report (Test Set):")
print(classification_report(y_test, y_pred_test, target_names=iris.target_names))

# %%
# Confusion Matrix
plt.figure(figsize=(8, 6))
cm = confusion_matrix(y_test, y_pred_test)
sns.heatmap(
    cm,
    annot=True,
    fmt="d",
    cmap="Blues",
    xticklabels=iris.target_names,
    yticklabels=iris.target_names,
)
plt.title("Confusion Matrix - Test Set")
plt.ylabel("True Label")
plt.xlabel("Predicted Label")
plt.show()

# %%
# Feature Importance
feature_importance = pd.DataFrame(
    {"feature": X.columns, "importance": rf_model.feature_importances_}
).sort_values("importance", ascending=False)

plt.figure(figsize=(10, 6))
sns.barplot(data=feature_importance, x="importance", y="feature")
plt.title("Feature Importance")
plt.xlabel("Importance Score")
plt.show()

print("Feature Importance:")
print(feature_importance)

# %% [markdown]
# ## 5. Cross-Validation

# %%
# Perform cross-validation
cv_scores = cross_val_score(rf_model, X_train_scaled, y_train, cv=5, scoring="accuracy")

print("Cross-Validation Scores:", cv_scores)
print(f"Mean CV Score: {cv_scores.mean():.4f} (+/- {cv_scores.std() * 2:.4f})")

# Visualize CV scores
plt.figure(figsize=(8, 6))
plt.boxplot(cv_scores)
plt.title("Cross-Validation Scores")
plt.ylabel("Accuracy")
plt.ylim(0.8, 1.0)
plt.grid(True, alpha=0.3)
plt.show()

# %% [markdown]
# ## 6. Save Model Artifacts

# %%
# Create models directory
models_dir = Path("../models")
models_dir.mkdir(exist_ok=True)

# Save the trained model
model_path = models_dir / "model.pkl"
with open(model_path, "wb") as f:
    pickle.dump(rf_model, f)
print(f"Model saved to: {model_path}")

# Save the scaler
scaler_path = models_dir / "scaler.pkl"
with open(scaler_path, "wb") as f:
    pickle.dump(scaler, f)
print(f"Scaler saved to: {scaler_path}")

# Save metrics
metrics = {
    "train_accuracy": float(train_accuracy),
    "test_accuracy": float(test_accuracy),
    "n_train_samples": len(X_train),
    "n_test_samples": len(X_test),
    "n_features": X.shape[1],
    "n_classes": len(y.unique()),
    "cv_mean": float(cv_scores.mean()),
    "cv_std": float(cv_scores.std()),
}

metrics_path = models_dir / "metrics.json"
with open(metrics_path, "w") as f:
    json.dump(metrics, f, indent=2)
print(f"Metrics saved to: {metrics_path}")

# Save model info
model_info = {
    "model_type": "RandomForestClassifier",
    "n_estimators": rf_model.n_estimators,
    "n_features": rf_model.n_features_in_,
    "feature_names": X.columns.tolist(),
    "classes": iris.target_names.tolist(),
}

info_path = models_dir / "model_info.json"
with open(info_path, "w") as f:
    json.dump(model_info, f, indent=2)
print(f"Model info saved to: {info_path}")

# %% [markdown]
# ## 7. Summary
#
# ### Model Performance
# - **Test Accuracy**: {:.2%} - The model correctly classifies {:.0f} out of every 100 samples
# - **Cross-Validation**: {:.2%} (+/- {:.2%}) - Consistent performance across different data splits
#
# ### Key Findings
# 1. The Random Forest model achieves excellent performance on the Iris dataset
# 2. Most important features are petal length and petal width
# 3. The model shows no signs of overfitting (similar train/test accuracy)
#
# ### Next Steps
# 1. Deploy the model using KServe for online inference
# 2. Set up monitoring for data drift detection
# 3. Create automated retraining pipeline
#
# The trained model and all artifacts have been saved and are ready for deployment in the Kubeflow pipeline.

# %%
print(
    f"""
Model Training Summary:
----------------------
Algorithm: Random Forest Classifier
Test Accuracy: {test_accuracy:.2%}
Cross-Validation: {cv_scores.mean():.2%} (+/- {cv_scores.std() * 2:.2%})
Training Samples: {len(X_train)}
Test Samples: {len(X_test)}

Model artifacts saved in: {models_dir.absolute()}
"""
)
