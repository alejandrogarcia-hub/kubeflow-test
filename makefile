.PHONY: format lint check clean install test pipeline requirements help train evaluate serve monitor compile submit notebooks demo

# Python source files
PYTHON_FILES = src/*.py src/pipelines/*.py notebooks/*.py

# Default target
default: help

# Help message
help:
	@echo "Kubeflow ML Pipeline Project"
	@echo "============================"
	@echo "Available commands:"
	@echo "  make install     - Install dependencies"
	@echo "  make test        - Run tests"
	@echo "  make lint        - Run linting"
	@echo "  make format      - Format code"
	@echo "  make pipeline    - Run format, lint, and tests"
	@echo "  make train       - Train the model"
	@echo "  make evaluate    - Evaluate the model"
	@echo "  make serve       - Start model serving API"
	@echo "  make monitor     - Run drift monitoring"
	@echo "  make compile     - Compile Kubeflow pipeline"
	@echo "  make submit      - Submit pipeline to Kubeflow"
	@echo "  make notebooks   - Convert Python files to Jupyter notebooks"
	@echo "  make demo        - Run full demo (train + evaluate)"
	@echo "  make clean       - Clean generated files"

# Install dependencies
install:
	uv sync

# Format code using ruff
format:
	uv run ruff format $(PYTHON_FILES)

# Run ruff linter
lint:
	uv run ruff check $(PYTHON_FILES)
	uv run ruff check --select I $(PYTHON_FILES)  # Import order
	uv run ruff check --select ERA $(PYTHON_FILES)  # Eradicate commented-out code
	uv run ruff check --select UP $(PYTHON_FILES)  # pyupgrade (modernize code)

lint_fix:
	uv run ruff check --fix $(PYTHON_FILES)
	uv run ruff check --fix --select I $(PYTHON_FILES)  # Import order
	uv run ruff check --fix --select ERA $(PYTHON_FILES)  # Eradicate commented-out code
	uv run ruff check --fix --select UP $(PYTHON_FILES)  # pyupgrade (modernize code)

# Fix auto-fixable issues
fix:
	uv run ruff check --fix $(PYTHON_FILES)

# Run all checks without modifying files
check:
	uv run ruff format --check $(PYTHON_FILES)
	uv run ruff check $(PYTHON_FILES)

# Run tests
test:
	uv run pytest tests/ -v

# ML Pipeline Commands
train:
	uv run python src/train_model.py

evaluate:
	uv run python src/evaluate_model.py

serve:
	uv run python src/serve_model.py

monitor:
	uv run python src/monitor_drift.py

# Kubeflow Commands
compile:
	uv run python run_pipeline.py --mode compile

submit:
	uv run python run_pipeline.py --mode submit

# Convert notebooks
notebooks:
	cd notebooks && uv run python convert_to_notebook.py

# Port forward to Kubeflow UI
port-forward:
	./port_forward_kfp.sh

# Check Kubeflow status
kf-status:
	kubectl get pods -n kubeflow | head -20

# Full demo flow
demo: clean train evaluate
	@echo "Demo completed! Check models/ directory for artifacts."

# Clean up python cache files and artifacts
clean:
	find . -type d -name "__pycache__" -exec rm -r {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type f -name ".coverage" -delete
	find . -type d -name "*.egg-info" -exec rm -r {} +
	find . -type d -name "*.egg" -exec rm -r {} +
	find . -type d -name ".pytest_cache" -exec rm -r {} +
	find . -type d -name ".ruff_cache" -exec rm -r {} +
	rm -rf models/*
	rm -f iris_pipeline.yaml

# Main pipeline (format, lint, test)
pipeline: format lint_fix test

# Generate requirements files
requirements:
	uv pip compile pyproject.toml -o requirements.txt
	uv pip compile pyproject.toml --group dev -o requirements-dev.txt