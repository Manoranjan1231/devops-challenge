#!/usr/bin/env bash
# Builds the image and deploys the full stack to whatever cluster your
# kubectl context currently points at (kind, minikube, k3s, etc).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-devops-challenge}"

echo "==> Building backend image"
docker build -t devops-challenge-backend:local ./app

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "==> Loading image into kind cluster '${CLUSTER_NAME}'"
  kind load docker-image devops-challenge-backend:local --name "${CLUSTER_NAME}"
elif command -v minikube >/dev/null && minikube status >/dev/null 2>&1; then
  echo "==> Loading image into minikube"
  minikube image load devops-challenge-backend:local
else
  echo "==> No kind/minikube cluster detected by name; assuming image is already reachable."
fi

echo "==> Applying manifests"
kubectl apply -f k8s/

echo "==> Waiting for rollout"
kubectl rollout status deployment/postgres -n devops-challenge --timeout=120s
kubectl rollout status deployment/backend -n devops-challenge --timeout=120s

echo "==> Done. Service exposed on NodePort 30080."
echo "    kubectl get svc -n devops-challenge"
