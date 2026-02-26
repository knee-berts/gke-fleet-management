#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Starting Multikueue Validation..."

PROJECT_ID="kubecon-fleets-demo-1"
REGION="us-central1"
MANAGEMENT_CLUSTER="management-cluster"

echo "Project: $PROJECT_ID"
echo "Management Cluster: $MANAGEMENT_CLUSTER"

# Get credentials for management cluster
gcloud container clusters get-credentials $MANAGEMENT_CLUSTER --region $REGION --project $PROJECT_ID

# Check for Key Multikueue CRDs
# Kueue CRDs: ClusterQueue, LocalQueue, Workload, ResourceFlavor
CRDS=("clusterqueues.kueue.x-k8s.io" "localqueues.kueue.x-k8s.io" "workloads.kueue.x-k8s.io" "resourceflavors.kueue.x-k8s.io")

for crd in "${CRDS[@]}"; do
  if kubectl get crd $crd > /dev/null 2>&1; then
    echo "✓ $crd found"
  else
    echo "✗ $crd NOT found"
    exit 1
  fi
done

TEST_NS="multikueue-validation-$(date +%s)"
CLUSTER_QUEUE="test-cluster-queue-$TEST_NS"
RESOURCE_FLAVOR="test-flavor-$TEST_NS"
LOCAL_QUEUE="test-local-queue"

echo "Creating test namespace: $TEST_NS"
kubectl create ns $TEST_NS

# Cleanup function
cleanup() {
  echo "Cleaning up..."
  kubectl delete ns $TEST_NS --ignore-not-found
  kubectl delete clusterqueue $CLUSTER_QUEUE --ignore-not-found
  kubectl delete resourceflavor $RESOURCE_FLAVOR --ignore-not-found
}
trap cleanup EXIT

# Create a ResourceFlavor
echo "Creating ResourceFlavor..."
cat <<EOF | kubectl apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: $RESOURCE_FLAVOR
EOF

# Create a ClusterQueue
echo "Creating ClusterQueue..."
cat <<EOF | kubectl apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: $CLUSTER_QUEUE
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory", "ephemeral-storage"]
    flavors:
    - name: $RESOURCE_FLAVOR
      resources:
      - name: "cpu"
        nominalQuota: 1
      - name: "memory"
        nominalQuota: 1Gi
      - name: "ephemeral-storage"
        nominalQuota: 1Gi
EOF

# Create a LocalQueue
echo "Creating LocalQueue in $TEST_NS..."
cat <<EOF | kubectl apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: $LOCAL_QUEUE
  namespace: $TEST_NS
spec:
  clusterQueue: $CLUSTER_QUEUE
EOF

# Create a Job
echo "Submitting a test Job..."
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: sample-job
  namespace: $TEST_NS
  labels:
    kueue.x-k8s.io/queue-name: $LOCAL_QUEUE
spec:
  template:
    spec:
      containers:
      - name: sample-job
        image: busybox
        command: ["sh", "-c", "echo Hello Multikueue! && sleep 5"]
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
      restartPolicy: Never
EOF

echo "Waiting for Job to complete..."
# Wait for job to complete
if kubectl wait --for=condition=complete job/sample-job -n $TEST_NS --timeout=120s; then
  echo "✓ Job completed successfully! Multikueue is working."
else
  echo "✗ Job failed to complete within timeout."
  echo "Checking Workload status..."
  kubectl get workloads -n $TEST_NS -o yaml
  exit 1
fi

echo "Validation succeeded!"
