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

echo "Starting Workloads Validation..."

# 1. Check Worker Clusters for Pods
for i in "${!WORKER_CLUSTERS[@]}"; do
  CLUSTER=${WORKER_CLUSTERS[$i]}
  CLUSTER_REGION=${WORKER_REGIONS[$i]}
  echo "Checking Worker Cluster: $CLUSTER..."
  
  gcloud container clusters get-credentials $CLUSTER --region $CLUSTER_REGION --project $PROJECT_ID
  
  # Check for gemma-server pods
  echo "Checking for gemma-server pods in namespace gemma-server..."
  if kubectl get pods -n gemma-server -l app=gemma-server --no-headers | grep -q "Running"; then
    echo -e "${GREEN}✓ gemma-server pods running on $CLUSTER${NC}"
  else
    echo -e "${RED}✗ gemma-server pods NOT found or not running on $CLUSTER${NC}"
    kubectl get pods -n gemma-server
    # Continue to check other clusters, but fail at end?
  fi
done

# 2. Check Hub Cluster for Route and Gateway
echo "Checking Hub Cluster: $HUB_CLUSTER..."
gcloud container clusters get-credentials $HUB_CLUSTER --region $REGION --project $PROJECT_ID

# Check HTTPRoute
echo "Checking HTTPRoute..."
if kubectl get httproute gemma-server-route -n gemma-server > /dev/null 2>&1; then
  echo -e "${GREEN}✓ HTTPRoute found${NC}"
else
  echo -e "${RED}✗ HTTPRoute gemma-server-route NOT found in gemma-server namespace${NC}"
  exit 1
fi

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway gemma-server-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}')

if [ -z "$GATEWAY_IP" ]; then
  echo -e "${RED}✗ Gateway has no IP${NC}"
  exit 1
fi

echo "Gateway IP: $GATEWAY_IP"

# 3. Connectivity Test
echo "Running Internal Connectivity Test (from Hub)..."
# Create a temp pod to curl the gateway
kubectl run curl-test-$(date +%s) --image=curlimages/curl --restart=Never --rm -i --tty --namespace=default -- \
  curl -v --connect-timeout 5 --max-time 10 http://$GATEWAY_IP/health

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Connectivity Test Passed!${NC}"
else
  echo -e "${RED}✗ Connectivity Test Failed${NC}"
  # Don't exit immediately, maybe pods are still starting up
  echo "Checking endpoint slices..."
  kubectl get endpointslice -n gemma-server
  exit 1
fi

echo -e "${GREEN}Validation succeeded! Workloads are accessible via Internal Gateway.${NC}"
