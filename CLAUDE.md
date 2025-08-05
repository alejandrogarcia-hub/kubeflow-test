# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Python project named "kubeflow-test" that requires Python 3.13 or higher. The project uses pyproject.toml for configuration and currently has a minimal structure with a main.py entry point.

### Project Objectives

The project is a simple Python application that uses the Kubeflow SDK to run a pipeline.
The main objective is to learn how to use the Kubeflow SDK to run a pipeline.

### Project Requirements

- end-to-end pipeline with Kubeflow SDK
- for data structures, use pydantic
- optimize code for speed and memory usage (e.g., list comprehensions, generators, vectorization, etc.)
- write tests (Unit, Functional, Integration)
  - use pytest
  - for unit tests, use the `@pytest.mark.unit` marker
  - for unit tests for the AAA framework
  - for unit test keep the test names short and descriptive
  - for unit tests, find edge cases
- Document the code using docstrings, google style
- Docstring shall be explicit and detailed, assume the reader is a junior developer, or data scientists, or a non-technical person
- use ruff for linting and formatting
- use a git action to run 'make pipeline'

### Project Structure

- `src/main.py` - Main entry point containing a simple hello world function
- `tests/` - Unit tests
- `pyproject.toml` - Project configuration file defining metadata and dependencies
- `pytest.ini` - pytest configuration file
- `makefile` - Makefile for running the pipeline
- `.gitignore` - gitignore file
- `.env` - environment variables file
- `.env.example` - environment variables example file
- `README.md` - project README file

## Development Commands

### Running the Application

ALWAYS run `make pipeline` to run the linting, formatter and tests.

```bash
uv run python main.py
```

### Installing Dependencies

Make sure to understand the difference between dev and non-dev dependencies.

For non-dev dependencies, use `uv add <python package>`.

For dev dependencies, use `uv add --dev <python package>`.

## Notes

- The project uses `uv` as the Python package manager
- The project is in early development stage with minimal functionality
- No testing framework or linting tools are currently configured
- To add dependencies, update the `dependencies` list in pyproject.toml
