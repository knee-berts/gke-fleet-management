#!/bin/bash
set -e

# Default values
LOCATION="us-central1"

# Usage function
usage() {
    echo "Usage: $0 <PROJECT_ID> [LOCATION]"
    echo "  PROJECT_ID: The Google Cloud Project ID"
    echo "  LOCATION: The location for the Artifact Registry (default: us-central1)"
    exit 1
}

# Check arguments
if [ -z "$1" ]; then
    usage
fi

PROJECT_ID=$1
if [ -n "$2" ]; then
    LOCATION=$2
fi

echo "Setting up gcp-auth-plugin for project $PROJECT_ID in $LOCATION..."

# Create Artifact Registry repository if it doesn't exist
if ! gcloud artifacts repositories describe gcp-auth-plugin --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; then
    echo "Creating Artifact Registry repository 'gcp-auth-plugin'..."
    gcloud artifacts repositories create gcp-auth-plugin \
        --repository-format=docker \
        --location="$LOCATION" \
        --project="$PROJECT_ID"
else
    echo "Artifact Registry repository 'gcp-auth-plugin' already exists."
fi

# Build and submit the image
SCRIPT_DIR=$(dirname "$(realpath "$0")")
SOURCE_DIR="$SCRIPT_DIR/../gcp-auth-plugin"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory $SOURCE_DIR not found!"
    exit 1
fi

echo "Building and submitting image from $SOURCE_DIR..."
gcloud builds submit "$SOURCE_DIR" \
   --project="$PROJECT_ID" \
   --region="$LOCATION" \
   --config="$SOURCE_DIR/cloudbuild.yaml"

echo "Prerequisites installed successfully!"
