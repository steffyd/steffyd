#!/bin/bash

# Setup script for Homepage Terraform infrastructure
# This script creates the necessary GCS bucket for Terraform state

set -e

PROJECT_ID="steffyd"
BUCKET_NAME="steffyd-terraform-state"

echo "Setting up Terraform state bucket for project: $PROJECT_ID"

# Check if gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Set the project
gcloud config set project $PROJECT_ID

# Create the GCS bucket for Terraform state (if it doesn't exist)
echo "Creating GCS bucket for Terraform state..."
if gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
    echo "Bucket $BUCKET_NAME already exists."
else
    gsutil mb gs://$BUCKET_NAME
    echo "Bucket $BUCKET_NAME created successfully."
fi

# Enable versioning on the bucket
echo "Enabling versioning on the bucket..."
gsutil versioning set on gs://$BUCKET_NAME

# Set lifecycle policy to prevent accidental deletion
echo "Setting lifecycle policy..."
cat > lifecycle.json << EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 90}
    }
  ]
}
EOF

gsutil lifecycle set lifecycle.json gs://$BUCKET_NAME
rm lifecycle.json

echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Copy terraform.tfvars.example to terraform.tfvars"
echo "2. Edit terraform.tfvars with your OAuth2 credentials"
echo "3. Run 'terraform init' to initialize the backend"
echo "4. Run 'terraform plan' to review the changes"
echo "5. Run 'terraform apply' to deploy the infrastructure"
