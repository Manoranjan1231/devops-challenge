#!/usr/bin/env bash
# Not meant to run unattended — this is a narrated checklist for the
# "Failure Debugging Walkthrough" section of the video. Run each block,
# talk through what you see, then move to the next.
set -euo pipefail
NS=devops-challenge

echo "### 1. Symptom: is the app reachable?"
echo "kubectl port-forward -n $NS svc/backend 8080:80 &"
echo "curl -i http://localhost:8080/"
echo "  -> expect connection to hang or return an error (no ready endpoints)"
echo

echo "### 2. Check pod status — are pods crashing, or just not ready?"
echo "kubectl get pods -n $NS -o wide"
echo "  -> STATUS should show 'Running' but READY column shows 0/1"
echo "     This immediately tells us it's a READINESS problem, not a crash."
echo

echo "### 3. Check the Service endpoints"
echo "kubectl get endpoints backend -n $NS"
echo "  -> if empty, Kubernetes has correctly pulled unready pods out of rotation"
echo "     this IS the system working as designed — traffic isn't being sent"
echo "     to broken pods. That's the point of the readiness probe."
echo

echo "### 4. Describe the pod for probe failure events"
echo "kubectl describe pod -n $NS -l app=backend"
echo "  -> look at the Events section: 'Readiness probe failed: HTTP probe failed with statuscode: 503'"
echo

echo "### 5. Check application logs for the actual error"
echo "kubectl logs -n $NS -l app=backend --tail=50"
echo "  -> look for 'DB init failed' / postgres auth error"
echo

echo "### 6. Hit the readiness endpoint directly to see the raw error"
echo "kubectl exec -n $NS deploy/backend -- wget -qO- http://localhost:3000/readyz || true"
echo "  -> should show {\"status\":\"not_ready\",\"db\":\"unreachable\",...}"
echo

echo "### 7. Inspect the config that changed"
echo "kubectl get secret backend-secret -n $NS -o jsonpath='{.data.DATABASE_URL}' | base64 -d"
echo "  -> spot the wrong password in the connection string"
echo

echo "### 8. Root cause confirmed: bad credential in backend-secret."
echo "    Fix: ./scripts/fix.sh"
