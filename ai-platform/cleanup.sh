#!/bin/bash
set -e

# Cleanup script for AI Platform Demo
# This script destroys resources in reverse dependency order:
# 4-workloads -> 3-multi-cluster-inference-gateway -> 2-multikueue -> 1-infrastructure

echo "⚠️  WARNING: This script will DESTROY all resources created by the AI Platform Demo."
echo "   Project: $GOOGLE_CLOUD_PROJECT (from environment)"
read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting cleanup."
    exit 1
fi

# Ensure project_id is set
if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    read -p "Enter Google Cloud Project ID: " GOOGLE_CLOUD_PROJECT
fi

export TF_VAR_project_id=$GOOGLE_CLOUD_PROJECT

echo "----------------------------------------------------------------"
echo "Step 1: Destroying Workloads (4-workloads)..."
echo "----------------------------------------------------------------"
cd 4-workloads
if [ -f "terraform.tfstate" ]; then
    terraform init
    terraform destroy -auto-approve
else
    echo "No state file found in 4-workloads, skipping..."
fi
cd ..

echo "----------------------------------------------------------------"
echo "Step 2: Destroying Gateway Infrastructure (3-multi-cluster-inference-gateway)..."
echo "----------------------------------------------------------------"
cd 3-multi-cluster-inference-gateway
if [ -f "terraform.tfstate" ]; then
    terraform init
    terraform destroy -auto-approve
else
    echo "No state file found in 3-multi-cluster-inference-gateway, skipping..."
fi
cd ..

echo "----------------------------------------------------------------"
echo "Step 3: Destroying Multikueue (2-multikueue)..."
echo "----------------------------------------------------------------"
cd 2-multikueue
if [ -f "terraform.tfstate" ]; then
    terraform init
    terraform destroy -auto-approve
else
    echo "No state file found in 2-multikueue, skipping..."
fi
cd ..

echo "----------------------------------------------------------------"
echo "Step 4: Destroying Base Infrastructure (1-infrastructure)..."
echo "----------------------------------------------------------------"
cd 1-infrastructure
if [ -f "terraform.tfstate" ]; then
    terraform init
    terraform destroy -auto-approve
else
    echo "No state file found in 1-infrastructure, skipping..."
fi
cd ..

echo "----------------------------------------------------------------"
echo "✅ Cleanup Complete!"
echo "----------------------------------------------------------------"
