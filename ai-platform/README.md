# ai-platform Demo

This directory contains a unified demonstration of **Multikueue** and **Multi-Cluster Inference Gateway** on Google Kubernetes Engine (GKE).

## Directory Structure

- **[1-infrastructure](./1-infrastructure)**: Contains the Service Infrastructure Terraform code. It provisions:
  - A Management (Hub) Cluster.
  - Worker Clusters (with L4 and H100 node pools).
  - Fleet registration, Workload Identity, and MCI.
  - Helm releases for ArgoCD.

- **[2-multikueue](./2-multikueue)**: Contains the Multikueue workload configuration.
  - Deploys Kueue Manager to the Hub and Kueue Agents to the workers.
  - Validates Multikueue functionality.

- **[3-multi-cluster-inference-gateway](./3-multi-cluster-inference-gateway)**: Contains the Multi-Cluster Inference Gateway workload configuration.

## Pre-requisites

1.  **Google Cloud Project**: You need a Google Cloud Project with billing enabled.
2.  **Terraform**: Install Terraform.
3.  **GCloud SDK**: Install the Google Cloud SDK.
4.  **kubectl**: Install kubectl.

## Usage

1.  **Infrastructure**:
    ```bash
    cd 1-infrastructure
    terraform init
    terraform apply -var="project_id=YOUR_PROJECT_ID"
    ```

2.  **Multikueue Workload**:
    ```bash
    cd ../2-multikueue
    terraform init
    terraform apply -var="project_id=YOUR_PROJECT_ID"
    ```

3.  **Multi-Cluster Inference Gateway Workload**:
    ```bash
    cd ../3-multi-cluster-inference-gateway
    terraform init
    terraform apply
    ```
