#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ID="kubecon-fleets-demo-1"
HUB_CLUSTER="management-cluster"
REGION="us-central1"
WORKER_CLUSTERS=("worker-cluster-us-east1" "worker-cluster-us-west1")
WORKER_REGIONS=("us-east1" "us-west1")

echo "Starting Gateway Infrastructure Validation..."

# 1. Check Hub Cluster
echo "Checking Hub Cluster: $HUB_CLUSTER..."
gcloud container clusters get-credentials $HUB_CLUSTER --region $REGION --project $PROJECT_ID

# Check CRD
if kubectl get crd inferenceobjectives.inference.networking.x-k8s.io > /dev/null 2>&1; then
  echo -e "${GREEN}✓ InferenceObjective CRD found on Hub${NC}"
else
  echo -e "${RED}✗ InferenceObjective CRD NOT found on Hub${NC}"
  exit 1
fi

# Check Gateway Class
if kubectl get gatewayclass gke-l7-cross-regional-internal-managed-mc > /dev/null 2>&1; then
  echo -e "${GREEN}✓ GatewayClass found${NC}"
else
  echo -e "${RED}✗ GatewayClass NOT found${NC}"
  exit 1
fi

# Check Gateway
echo "Checking Gateway status..."
GATEWAY_NAME="gemma-server-gateway"
kubectl wait --for=condition=Programmed gateway/$GATEWAY_NAME -n gateway-system --timeout=300s

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Gateway $GATEWAY_NAME is Programmed${NC}"
  
  # Get Address
  ADDRESS=$(kubectl get gateway $GATEWAY_NAME -n gateway-system -o jsonpath='{.status.addresses[0].value}')
  if [ ! -z "$ADDRESS" ]; then
    echo -e "${GREEN}✓ Gateway Address assigned: $ADDRESS${NC}"
  else
    echo -e "${RED}✗ Gateway has no address assigned${NC}"
    kubectl get gateway $GATEWAY_NAME -n gateway-system -o yaml
    exit 1
  fi
else
  echo -e "${RED}✗ Gateway failed to program within timeout${NC}"
  kubectl get gateway $GATEWAY_NAME -n gateway-system -o yaml
  exit 1
fi

# 2. Check Worker Clusters
for i in "${!WORKER_CLUSTERS[@]}"; do
  CLUSTER=${WORKER_CLUSTERS[$i]}
  CLUSTER_REGION=${WORKER_REGIONS[$i]}
  echo "Checking Worker Cluster: $CLUSTER ($CLUSTER_REGION)..."
  
  gcloud container clusters get-credentials $CLUSTER --region $CLUSTER_REGION --project $PROJECT_ID
  
  if kubectl get crd inferenceobjectives.inference.networking.x-k8s.io > /dev/null 2>&1; then
    echo -e "${GREEN}✓ InferenceObjective CRD found on $CLUSTER${NC}"
  else
    echo -e "${RED}✗ InferenceObjective CRD NOT found on $CLUSTER${NC}"
    exit 1
  fi
done

echo -e "${GREEN}Validation succeeded! Gateway Infra is ready.${NC}"
