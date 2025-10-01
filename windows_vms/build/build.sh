#!/bin/bash

# Build script for creating kasm-windows-startup.zip
# This script can be run locally or in GitLab CI

set -e  # Exit on any error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
ARCHIVE_NAME="kasm-windows-startup.zip"
SOURCE_PATH="src"
DIST_DIR="dist"
TMP_DIR="$DIST_DIR/.tmp"
VERSIONS_FILE="versions.yaml"

echo "=== Build Script Started ==="
echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo "Archive name: $ARCHIVE_NAME"
echo "Source path: $SOURCE_PATH"
echo "Distribution directory: $DIST_DIR"
echo "Temporary directory: $TMP_DIR"

# Check if src directory exists
if [ ! -d "$PROJECT_ROOT/$SOURCE_PATH" ]; then
    echo "Error: Source directory not found at $PROJECT_ROOT/$SOURCE_PATH"
    exit 1
fi

# Check if Python is available and determine which command to use
PYTHON_CMD=""

# Try different Python commands in order of preference
for cmd in python python3 py; do
    if command -v "$cmd" &> /dev/null; then
        # Test if the command actually works (not just a Microsoft Store redirect)
        if "$cmd" --version &> /dev/null; then
            PYTHON_CMD="$cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    echo "Error: No working Python installation found"
    echo "Please install Python or ensure it's available in your PATH"
    exit 1
fi

echo "Using Python command: $PYTHON_CMD"

# Change to project root directory
cd "$PROJECT_ROOT"

# Clean and create temporary directory
if [ -d "$TMP_DIR" ]; then
    echo "Removing existing $TMP_DIR directory..."
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"

# Copy VERSIONS_FILE to temporary directory
if [ -f "$VERSIONS_FILE" ]; then
    echo "Copying $VERSIONS_FILE to $TMP_DIR/"
    cp "$VERSIONS_FILE" "$TMP_DIR/"
    echo "Successfully copied $VERSIONS_FILE"
else
    echo "Error: $VERSIONS_FILE not found at $PROJECT_ROOT/$VERSIONS_FILE"
    exit 1
fi

# Copy contents of SOURCE_PATH to temporary directory
echo "Copying contents of $SOURCE_PATH to $TMP_DIR/"
if [ -d "$SOURCE_PATH" ]; then
    if cp -r "$SOURCE_PATH"/* "$TMP_DIR/" 2>/dev/null; then
        echo "Successfully copied contents of $SOURCE_PATH to $TMP_DIR/"
    else
        echo "Warning: No files found in $SOURCE_PATH or copy failed"
    fi
else
    echo "Warning: Source directory $SOURCE_PATH not found"
fi

echo "Creating archive from $SOURCE_PATH directory..."

# Call the Python template processing script
$PYTHON_CMD "$SCRIPT_DIR/template.py" "$TMP_DIR" "$VERSIONS_FILE"

# Call the Python packaging script with arguments
$PYTHON_CMD "$SCRIPT_DIR/package.py" "$ARCHIVE_NAME" "$TMP_DIR"

# Check if the archive was created successfully
if [ -f "$PROJECT_ROOT/$DIST_DIR/$ARCHIVE_NAME" ]; then
    echo "=== Build Successful ==="
    echo "Archive created: $DIST_DIR/$ARCHIVE_NAME"
    echo "Archive size: $(du -h "$PROJECT_ROOT/$DIST_DIR/$ARCHIVE_NAME" | cut -f1)"
else
    echo "Error: Archive was not created at $DIST_DIR/$ARCHIVE_NAME"
    exit 1
fi