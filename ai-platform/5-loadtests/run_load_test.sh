#!/bin/bash
set -e

# Gateway IP from validation Step or user input
GATEWAY_IP=$(kubectl get gateway gemma-server-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}' --context gke_kubecon-fleets-demo-1_us-central1_management-cluster 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    # Fallback try current context
    GATEWAY_IP=$(kubectl get gateway gemma-server-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}')
fi

if [ -z "$GATEWAY_IP" ]; then
    echo "Error: Could not find Gateway IP. Please ensure Gateway 'gemma-server-gateway' is programmed."
    exit 1
fi

echo "Gateway IP: $GATEWAY_IP"

# Prepare Manifest
# Read python script content and indent it for YAML (4 spaces)
SCRIPT_CONTENT=$(cat load_test.py | sed 's/^/    /')
# Escape valid yaml special chars if needed, but simple python usually ok inside block scalar
# Actually, simpler to just kubectl create configmap directly then apply jobs.

# Deploy on Hub? No, these jobs should run where the clients are.
# But "us-east1" and "us-west1" nodes are in worker clusters!
# "topology.kubernetes.io/region: us-east1" only exists in worker-cluster-us-east1.
# So I must deploy 'load-test-east' to 'worker-cluster-us-east1' and 'load-test-west' to 'worker-cluster-us-west1'.
# I cannot deploy them to Hub and expect them to schedule on workers unless it's a multi-cluster scheduler (which is what we are demoing, but specifically for Workloads, not these test jobs).
# These test jobs represent "Clients".

# Deploy on Workers
echo "Starting Load Test Job in US-East1..."
gcloud container clusters get-credentials worker-cluster-us-east1 --region us-east1 --project kubecon-fleets-demo-1 > /dev/null 2>&1

kubectl delete configmap load-test-script --ignore-not-found > /dev/null 2>&1
kubectl create configmap load-test-script --from-file=load_test.py
kubectl delete job load-test-east --ignore-not-found > /dev/null 2>&1

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test-east
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      containers:
      - name: load-test
        image: python:3.9-slim
        command: ["/bin/sh", "-c"]
        args:
        - |
          pip install requests > /dev/null 2>&1 || true
          python3 /scripts/load_test.py --url http://${GATEWAY_IP} --model google/gemma-3-1b-it --region us-east1 --duration 15 --concurrency 4
        volumeMounts:
        - name: script-vol
          mountPath: /scripts
      restartPolicy: Never
      volumes:
      - name: script-vol
        configMap:
          name: load-test-script
EOF

echo "Starting Load Test Job in US-West1..."
gcloud container clusters get-credentials worker-cluster-us-west1 --region us-west1 --project kubecon-fleets-demo-1 > /dev/null 2>&1

kubectl delete configmap load-test-script --ignore-not-found > /dev/null 2>&1
kubectl create configmap load-test-script --from-file=load_test.py
kubectl delete job load-test-west --ignore-not-found > /dev/null 2>&1

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test-west
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      containers:
      - name: load-test
        image: python:3.9-slim
        command: ["/bin/sh", "-c"]
        args:
        - |
          pip install requests > /dev/null 2>&1 || true
          python3 /scripts/load_test.py --url http://${GATEWAY_IP} --model google/gemma-3-1b-it --region us-west1 --duration 15 --concurrency 4
        volumeMounts:
        - name: script-vol
          mountPath: /scripts
      restartPolicy: Never
      volumes:
      - name: script-vol
        configMap:
          name: load-test-script
EOF

echo "Waiting for tests to complete..."
sleep 5

# Function to wait for job completion
wait_for_job() {
    CLUSTER=$1
    REGION=$2
    JOB_NAME=$3
    echo "Waiting for $JOB_NAME on $CLUSTER..."
    gcloud container clusters get-credentials $CLUSTER --region $REGION --project kubecon-fleets-demo-1 > /dev/null 2>&1
    kubectl wait --for=condition=complete job/$JOB_NAME --timeout=300s > /dev/null 2>&1
}

wait_for_job "worker-cluster-us-east1" "us-east1" "load-test-east" &
PID_EAST=$!
wait_for_job "worker-cluster-us-west1" "us-west1" "load-test-west" &
PID_WEST=$!

wait $PID_EAST
wait $PID_WEST

echo ""
echo "=========================================="
echo "        LOAD TEST RESULTS"
echo "=========================================="

echo "Fetching logs from US-East1..."
gcloud container clusters get-credentials worker-cluster-us-east1 --region us-east1 --project kubecon-fleets-demo-1 > /dev/null 2>&1
kubectl logs job/load-test-east

echo ""
echo "Fetching logs from US-West1..."
gcloud container clusters get-credentials worker-cluster-us-west1 --region us-west1 --project kubecon-fleets-demo-1 > /dev/null 2>&1
kubectl logs job/load-test-west
