#!/usr/bin/env python3
"""
Convert Python files with cell markers to Jupyter notebooks.

This script converts Python files that use the # %% cell marker
convention into proper Jupyter notebooks.
"""

import json
from pathlib import Path
from typing import Any


def parse_py_file(content: str) -> list[dict[str, Any]]:
    """
    Parse a Python file with cell markers into notebook cells.

    Args:
        content: Python file content

    Returns:
        List of cell dictionaries
    """
    cells = []
    current_cell_lines = []
    current_cell_type = "code"

    lines = content.split("\n")
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check for cell marker
        if line.strip().startswith("# %%"):
            # Save previous cell if it has content
            if current_cell_lines and any(line.strip() for line in current_cell_lines):
                cells.append(
                    {"cell_type": current_cell_type, "source": current_cell_lines}
                )

            # Determine cell type
            if "[markdown]" in line:
                current_cell_type = "markdown"
                current_cell_lines = []
                # Skip the marker line
                i += 1
                # Process markdown cell
                while i < len(lines) and not lines[i].strip().startswith("# %%"):
                    # Remove leading '# ' from markdown lines
                    if lines[i].startswith("# "):
                        current_cell_lines.append(lines[i][2:])
                    else:
                        current_cell_lines.append(lines[i])
                    i += 1
                i -= 1  # Back up one line
            else:
                current_cell_type = "code"
                current_cell_lines = []
        else:
            current_cell_lines.append(line)

        i += 1

    # Don't forget the last cell
    if current_cell_lines and any(line.strip() for line in current_cell_lines):
        cells.append({"cell_type": current_cell_type, "source": current_cell_lines})

    return cells


def create_notebook(cells: list[dict[str, Any]]) -> dict[str, Any]:
    """
    Create a notebook structure from cells.

    Args:
        cells: List of cell dictionaries

    Returns:
        Notebook dictionary
    """
    notebook_cells = []

    for cell in cells:
        if cell["cell_type"] == "markdown":
            notebook_cells.append(
                {
                    "cell_type": "markdown",
                    "metadata": {},
                    "source": [line + "\n" for line in cell["source"]],
                }
            )
        else:
            # Remove empty lines from the beginning and end of code cells
            source_lines = cell["source"]
            while source_lines and not source_lines[0].strip():
                source_lines.pop(0)
            while source_lines and not source_lines[-1].strip():
                source_lines.pop()

            notebook_cells.append(
                {
                    "cell_type": "code",
                    "execution_count": None,
                    "metadata": {},
                    "outputs": [],
                    "source": [line + "\n" for line in source_lines],
                }
            )

    notebook = {
        "cells": notebook_cells,
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {
                "codemirror_mode": {"name": "ipython", "version": 3},
                "file_extension": ".py",
                "mimetype": "text/x-python",
                "name": "python",
                "nbconvert_exporter": "python",
                "pygments_lexer": "ipython3",
                "version": "3.11.0",
            },
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }

    return notebook


def convert_py_to_ipynb(py_file: Path, ipynb_file: Path) -> None:
    """
    Convert a Python file to a Jupyter notebook.

    Args:
        py_file: Input Python file path
        ipynb_file: Output notebook file path
    """
    # Read the Python file
    content = py_file.read_text()

    # Parse into cells
    cells = parse_py_file(content)

    # Create notebook structure
    notebook = create_notebook(cells)

    # Write the notebook
    with open(ipynb_file, "w") as f:
        json.dump(notebook, f, indent=2)

    print(f"Converted {py_file} to {ipynb_file}")


def main():
    """Convert all Python files in the notebooks directory to Jupyter notebooks."""
    notebooks_dir = Path(__file__).parent

    # Find all .py files (except this script)
    py_files = [
        f for f in notebooks_dir.glob("*.py") if f.name != "convert_to_notebook.py"
    ]

    for py_file in py_files:
        ipynb_file = py_file.with_suffix(".ipynb")
        try:
            convert_py_to_ipynb(py_file, ipynb_file)
        except Exception as e:
            print(f"Error converting {py_file}: {e}")


if __name__ == "__main__":
    main()
