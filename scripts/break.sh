#!/usr/bin/env bash
# FAILURE SIMULATION: injects a bad DATABASE_URL (wrong password) into
# the backend Secret and rolls the deployment, reproducing a real
# database-connectivity outage caused by a bad environment variable.
set -euo pipefail

NS=devops-challenge

echo "==> [BEFORE] current backend-secret DATABASE_URL:"
kubectl get secret backend-secret -n "$NS" -o jsonpath='{.data.DATABASE_URL}' | base64 -d
echo

echo "==> Injecting a BROKEN DATABASE_URL (wrong password)..."
kubectl patch secret backend-secret -n "$NS" --type merge -p \
  '{"stringData": {"DATABASE_URL": "postgresql://appuser:WRONG_PASSWORD@postgres:5432/appdb"}}'

echo "==> Restarting backend so pods pick up the bad credential..."
kubectl rollout restart deployment/backend -n "$NS"

echo
echo "==> Failure injected. Now go observe it:"
echo "    kubectl get pods -n $NS -w"
echo "    kubectl get endpoints backend -n $NS"
echo "    kubectl logs -n $NS -l app=backend --tail=50"
echo "    kubectl describe pod -n $NS -l app=backend"
