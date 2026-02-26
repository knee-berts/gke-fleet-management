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

4.  **Workloads**:
    ```bash
    cd ../4-workloads
    terraform init
    export TF_VAR_hf_api_token="YOUR_hf_..._TOKEN"
    terraform apply
    ```

## Cleanup

To tear down all resources and restore the project to a clean state, run the provided cleanup script:

```bash
./cleanup.sh
```

./cleanup.sh
```

## Known Issues

### Multi-Cluster Inference Gateway (MCIGW) - InferencePool

The `InferencePool` resource is currently not functioning as expected due to a missing `inference-picker` component in the provided samples.

- **Symptom**: Load tests fail with `500 Internal Server Error`, and the `InferencePool` status shows no endpoints.
- **Cause**: The `InferencePool` relies on an `endpointPickerRef` to select backend endpoints. The `inference-picker` deployment included in the sample uses a placeholder image (`gcr.io/google-samples/hello-app:1.0`), which lacks the necessary logic to populate the pool.
- **Investigation**:
  - The `InferencePool` CRD exists and is valid.
  - The `inference-picker` source code is not present in the `multi-cluster-orchestrator` repository.
  - The upstream `gateway-api-inference-extension` repository contains the `epp` (Endpoint Picker Plugin) source, but it requires a complex build and configuration (likely including sidecars) that is not documented in the sample.
- **Resolution**: Configured `inference-picker` to use the upstream `epp` staging image and injected a `ConfigMap` with the required `EndpointPickerConfig`.
