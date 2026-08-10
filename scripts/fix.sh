#!/usr/bin/env bash
# Restores the correct DATABASE_URL and rolls the deployment.
set -euo pipefail
NS=devops-challenge

echo "==> Restoring correct DATABASE_URL..."
kubectl patch secret backend-secret -n "$NS" --type merge -p \
  '{"stringData": {"DATABASE_URL": "postgresql://appuser:SuperSecretPassword123@postgres:5432/appdb"}}'

echo "==> Restarting backend..."
kubectl rollout restart deployment/backend -n "$NS"
kubectl rollout status deployment/backend -n "$NS" --timeout=90s

echo "==> Verifying recovery..."
sleep 3
kubectl get endpoints backend -n "$NS"
kubectl get pods -n "$NS" -l app=backend

echo "==> Fixed. Pods should now show READY 1/1 and the Service should have endpoints again."
