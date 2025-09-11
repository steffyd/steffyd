#!/bin/bash

# Setup script for Mealie Terraform state bucket
# This script creates the GCS bucket for storing Terraform state

set -e

PROJECT_ID="steffyd"
BUCKET_NAME="steffyd-terraform-state"

echo "Setting up Terraform state bucket for Mealie service..."

# Check if gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "Error: Not authenticated with gcloud. Please run 'gcloud auth login' first."
    exit 1
fi

# Set the project
gcloud config set project $PROJECT_ID

# Create the bucket if it doesn't exist
if ! gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
    echo "Creating GCS bucket: $BUCKET_NAME"
    gsutil mb -p $PROJECT_ID -c STANDARD -l US gs://$BUCKET_NAME
    
    # Enable versioning
    gsutil versioning set on gs://$BUCKET_NAME
    
    echo "Bucket created successfully!"
else
    echo "Bucket $BUCKET_NAME already exists."
fi

echo "Terraform state bucket setup complete!"
echo "You can now run 'terraform init' to initialize Terraform with the remote state backend."
