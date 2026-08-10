# DevOps Infra Challenge — Minimal Production-Style Stack

A tiny Node/Express backend + Postgres, deployed to Kubernetes, built and
deployed by GitHub Actions, with readiness/liveness probes as the
reliability improvement, plus a scripted failure/debug scenario.

## Stack

- **Backend**: Node.js/Express (`app/`) — `/`, `POST /items`, `/healthz` (liveness), `/readyz` (readiness, checks DB)
- **Database**: Postgres 16 (official image), backed by a PVC
- **Kubernetes**: raw manifests in `k8s/` (no Helm — kept explicit on purpose)
- **CI/CD**: `.github/workflows/ci-cd.yml` — builds image, pushes to GHCR, spins up an ephemeral `kind` cluster in the runner, deploys, smoke-tests
- **Reliability feature**: readiness vs. liveness probe separation
- **Failure scenario**: bad `DATABASE_URL` credential → DB connectivity outage

---

## 1. Local setup (for your live demo)

Prereqs: Docker, `kubectl`, `kind` (or minikube), Node 20 (only needed if you want to run tests locally).

```bash
# 1. Create a cluster
kind create cluster --name devops-challenge

# 2. Build + deploy everything
./scripts/deploy-local.sh

# 3. Check it's up
kubectl get all -n devops-challenge

# 4. Talk to it
kubectl port-forward -n devops-challenge svc/backend 8080:80
curl http://localhost:8080/readyz
curl -X POST http://localhost:8080/items -H 'Content-Type: application/json' -d '{"name":"first item"}'
curl http://localhost:8080/
```

## 2. CI/CD

Push this repo to GitHub. `.github/workflows/ci-cd.yml` runs on every push to `main`:

1. **build-and-test**: installs deps, runs `npm test` (smoke test), builds the Docker image, pushes to `ghcr.io/<you>/<repo>-backend:<sha>` and `:latest`.
2. **deploy**: spins up a fresh `kind` cluster inside the runner, creates a GHCR pull secret, `kubectl apply -f k8s/`, waits for rollout, then curls `/readyz` and `/` as a smoke test. On failure it dumps `describe`/`logs` automatically.

This is a real, ephemeral cluster doing real `kubectl apply` — not a managed one-click deploy. It proves the pipeline can go from `git push` to a running, health-checked service with zero manual steps. (For a persistent environment you'd point `deploy` at a long-lived cluster instead of `kind`, but the mechanics are identical.)

## 3. Reliability improvement: readiness vs. liveness probes

**Why I picked this one**: probes are the single reliability primitive that determines whether Kubernetes routes traffic correctly and restarts pods correctly. Get it wrong and you get either (a) crash-loop storms from a flaky dependency, or (b) traffic silently sent to broken pods. It's foundational — most of the other options (autoscaling, canary, circuit breakers) are built on top of health signals being correct in the first place.

**What problem it solves**: without probes, Kubernetes considers a pod "ready" the instant its process starts, even if the app hasn't connected to its database yet, or has lost that connection later. Traffic gets routed to pods that can't actually serve requests, and the platform has no signal to restart pods that are truly stuck vs. pods that are just waiting on a dependency.

**How it's implemented here** (`k8s/04-backend-deployment.yaml`):
- `livenessProbe` → `GET /healthz`, checks **only** that the Node process is responsive. If this fails, kubelet **kills and restarts** the container.
- `readinessProbe` → `GET /readyz`, checks that the app can reach Postgres (`SELECT 1`). If this fails, the pod is **pulled out of the Service's endpoints** — no restart, just no traffic — until it recovers.

**The tradeoff**: separating these two checks is more correct, but it's also more code paths to get right, and probe tuning is a genuine ongoing cost. Too-aggressive `failureThreshold`/`periodSeconds` causes unnecessary restarts during brief blips (e.g. a DB failover); too-lax settings mean users hit a broken pod for longer before it's pulled from rotation. There's no universally correct value — it has to be tuned against your dependency's real failure modes. I also deliberately made the app *not* crash on DB errors (it retries in the background) specifically so a DB outage shows up as a readiness failure, not a restart storm — which is itself a design decision with a tradeoff: if the DB is down for a very long time, you now have "successfully running but permanently not-ready" pods sitting around consuming resources indefinitely, rather than being cleaned up.

## 4. Failure simulation: bad DB credential

```bash
./scripts/break.sh              # injects a wrong password into backend-secret, restarts backend
cat scripts/debug-checklist.sh  # narrated commands for the debugging walkthrough
./scripts/fix.sh                # restores the correct secret and verifies recovery
```

**What actually happens**: the pods stay `Running` (liveness passes — the process is fine) but `READY` shows `0/1` (readiness fails — DB auth rejected). The Service's endpoint list empties out, so no traffic reaches the broken pods even though `kubectl get pods` still shows them as up. This is exactly why liveness and readiness are separate checks: a crash-only health check would either falsely restart healthy processes or (worse) never catch this class of failure at all.

**Debugging sequence** (see `scripts/debug-checklist.sh` for the exact commands):
1. `curl` the service → hangs/fails
2. `kubectl get pods` → Running, but not Ready — rules out "container crashed", points at readiness
3. `kubectl get endpoints backend` → empty — confirms Kubernetes correctly removed the pod from rotation
4. `kubectl describe pod` → Events show `Readiness probe failed: ... statuscode: 503`
5. `kubectl logs` → app logs show a Postgres auth error
6. Decode the Secret → spot the wrong password
7. Fix: restore correct secret, `kubectl rollout restart`, confirm `READY 1/1` and endpoints repopulate

## 5. Tradeoffs / what I simplified / what's next

**Simplified for the 90-minute scope:**
- Secrets are plain `Secret` objects checked into manifests (base64, not encrypted-at-rest-in-git). Fine for a demo; not fine for real production.
- Single Postgres replica, no automated backups, `Recreate` strategy means a brief outage on every DB pod update.
- No Ingress/TLS — backend exposed via `NodePort` for simplicity.
- No autoscaling — fixed 2 replicas.
- CI/CD deploys to a throwaway `kind` cluster inside the Actions runner rather than a persistent cloud cluster, so there's no real continuity between runs (nothing to roll back *to* from a previous deploy).

**What would break at scale:**
- Single Postgres instance is a hard bottleneck and single point of failure — no read replicas, no failover.
- `NodePort` doesn't scale past one node's IP in any meaningful way; you'd need an Ingress controller + LoadBalancer.
- No resource-based autoscaling means either over-provisioning (waste) or falling over under load.
- No centralized logging/metrics — right now "observability" is `kubectl logs`, which doesn't scale past a handful of pods.

**What I'd add for real production:**
- External Secrets Operator or Vault instead of plain Secrets.
- Managed Postgres (RDS/Cloud SQL) with automated backups and replicas, or a proper Postgres operator (e.g. CloudNativePG) if self-hosting.
- Ingress + cert-manager for TLS, HPA for autoscaling, PodDisruptionBudgets.
- Prometheus + Grafana (or a managed equivalent) for metrics, and structured logs shipped to a log aggregator.
- A persistent staging/prod cluster with ArgoCD doing GitOps-style continuous deployment instead of `kubectl apply` from a CI job, so deploys are declarative and diffable, and rollback is `git revert`.

---

## Video script (maps directly to the four required sections)

**1. Live Demo (3–4 min)**
- `kubectl get all -n devops-challenge` — show everything running
- `curl` the running service, POST an item, GET it back
- Push a trivial commit, switch to GitHub Actions tab, show the pipeline running build → push image → deploy → smoke test, green checkmark

**2. Architecture Walkthrough (2–3 min)**
- Draw/describe: GitHub push → Actions builds image → pushes to GHCR → ephemeral kind cluster → `kubectl apply` → rollout → smoke test
- Explain the namespace/ConfigMap/Secret/Deployment/Service layout in `k8s/`
- Explain the readiness/liveness design decision (section 3 above) — why, what problem, what tradeoff

**3. Failure Debugging Walkthrough (2–3 min)**
- Run `./scripts/break.sh` on camera
- Walk the `debug-checklist.sh` sequence live: symptom → pod status → endpoints → describe → logs → root cause
- Run `./scripts/fix.sh`, show recovery

**4. Tradeoff Discussion (1–2 min)**
- Walk through the "Tradeoffs / what I simplified" section above
