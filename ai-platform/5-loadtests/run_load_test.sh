#!/bin/bash
set -e

# Gateway IP from validation Step or user input
GATEWAY_IP=$(kubectl get gateway gemma-server-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}' --context gke_kubecon-fleets-demo-0_us-central1_ai-management-cluster 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    # Fallback try current context
    GATEWAY_IP=$(kubectl get gateway gemma-server-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}')
fi

if [ -z "$GATEWAY_IP" ]; then
    echo "Error: Could not find Gateway IP. Please ensure Gateway 'gemma-server-gateway' is programmed."
    exit 1
fi

echo "Gateway IP: $GATEWAY_IP"

# Deploy on Workers
echo "Starting Load Test Job in US-East4..."
gcloud container clusters get-credentials ai-worker-us-east4 --region us-east4 --project kubecon-fleets-demo-0 > /dev/null 2>&1

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
          python3 /scripts/load_test.py --url http://${GATEWAY_IP} --model google/gemma-3-1b-it --region us-east4 --duration 15 --concurrency 4
        volumeMounts:
        - name: script-vol
          mountPath: /scripts
      restartPolicy: Never
      volumes:
      - name: script-vol
        configMap:
          name: load-test-script
EOF

echo "Starting Load Test Job in US-Central1..."
gcloud container clusters get-credentials ai-worker-us-central1 --region us-central1 --project kubecon-fleets-demo-0 > /dev/null 2>&1

kubectl delete configmap load-test-script --ignore-not-found > /dev/null 2>&1
kubectl create configmap load-test-script --from-file=load_test.py
kubectl delete job load-test-central --ignore-not-found > /dev/null 2>&1

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test-central
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
          python3 /scripts/load_test.py --url http://${GATEWAY_IP} --model google/gemma-3-1b-it --region us-central1 --duration 15 --concurrency 4
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
    gcloud container clusters get-credentials $CLUSTER --region $REGION --project kubecon-fleets-demo-0 > /dev/null 2>&1
    kubectl wait --for=condition=complete job/$JOB_NAME --timeout=300s > /dev/null 2>&1
}

wait_for_job "ai-worker-us-east4" "us-east4" "load-test-east" &
PID_EAST=$!
wait_for_job "ai-worker-us-central1" "us-central1" "load-test-central" &
PID_CENTRAL=$!

wait $PID_EAST
wait $PID_CENTRAL

echo ""
echo "=========================================="
echo "        LOAD TEST RESULTS"
echo "=========================================="

echo "Fetching logs from US-East4..."
gcloud container clusters get-credentials ai-worker-us-east4 --region us-east4 --project kubecon-fleets-demo-0 > /dev/null 2>&1
kubectl logs job/load-test-east

echo ""
echo "Fetching logs from US-Central1..."
gcloud container clusters get-credentials ai-worker-us-central1 --region us-central1 --project kubecon-fleets-demo-0 > /dev/null 2>&1
kubectl logs job/load-test-central
