# DSO202 Assignment 4: Evidence

**Student:** Pema Dolker (02230294)

Every item shows the command I ran and its output, copied from my terminal. Credential values and the sealing key never appear here. Screenshots are in `docs/img/` and only where the brief asks for one.

---

## Task 1: Repository, chart contract and cluster

### 1.1 Tool check (section 3.2)

```text
$ docker version --format '{{.Server.Version}}'
TODO-PASTE
$ kind version
TODO-PASTE
$ kubectl version --client
TODO-PASTE
$ helm version --short
TODO-PASTE
$ git --version
TODO-PASTE
$ argocd version --client
TODO-PASTE
$ kubeseal --version
TODO-PASTE
```

```text
$ helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
$ helm repo update
$ helm search repo sealed-secrets/sealed-secrets --versions | head -5
TODO-PASTE (chart 2.20.0 must be in the list)
```

### 1.2 Chart contract

| # | Requirement | Where it is satisfied (file and key) |
|---|---|---|
| C1 | Image repository and tag are values; no tag in a template | `values.yaml`: `images.<tier>.repository` and `images.<tier>.tag`; tags set in `environments/<env>/values.yaml`. `_helpers.tpl`: `tasktracker.image` uses `required` with no fallback. |
| C2 | Per-tier configuration from values; a new backend variable is a values change | `values.yaml`: `backend.env`, `frontend.env`, `database.env` (maps). Rendered by `tasktracker.extraEnv` in `_helpers.tpl`, included in all three workload templates. |
| C3 | Chart never renders a Secret; Pods read `existingSecret` | `values.yaml`: `credentials.existingSecret`; set to `tasktracker-credentials` in both environment files. A3 `secret.yaml` removed. `tasktracker.secretName` has no fallback. |
| C4 | Readiness probes on all three tiers | `db-statefulset.yaml`: `pg_isready` over TCP. `backend-deployment.yaml`: `GET /api/status`. `frontend-deployment.yaml`: `GET /`. |
| C5 | Sync waves: database 0, backend 1, frontend 2 | `metadata.annotations."argocd.argoproj.io/sync-wave"` in `db-statefulset.yaml` ("0"), `backend-deployment.yaml` ("1"), `frontend-deployment.yaml` ("2"). |
| C6 | `progressDeadlineSeconds: 120` on backend and frontend | `values.yaml`: `progressDeadlineSeconds: 120`, used in `spec.progressDeadlineSeconds` of both Deployments. |
| C7 | Requests and limits on every container | `values.yaml`: `database.resources`, `backend.resources`, `frontend.resources`; `smoke-test-job.yaml`: `resources`. The schema requires both requests and limits. |
| C8 | No Namespace, ResourceQuota, LimitRange, Role, RoleBinding in the chart | A3 `quota.yaml` removed; these are in `platform/<env>/`. The kind list below shows none of them. |
| C9 | Any Ingress disabled by default | The chart has no Ingress template at all. |
| C10 | Frontend Service is NodePort, port number is a value | `frontend-service.yaml`: `spec.type` and `nodePort` from `frontend.service.*`; 30080 in `environments/dev/values.yaml`, 30081 in `environments/staging/values.yaml`. |
| C11 | `helm lint` clean, `helm template` works for both environments | Output below. |

### 1.3 helm lint and the kinds the chart renders

```text
$ helm lint charts/tasktracker -f environments/dev/values.yaml
TODO-PASTE
$ helm lint charts/tasktracker -f environments/staging/values.yaml
TODO-PASTE
$ helm template tasktracker charts/tasktracker -f environments/dev/values.yaml | grep '^kind:' | sort | uniq -c
TODO-PASTE
```

### 1.4 Cluster

```text
$ kind get clusters
TODO-PASTE
$ kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
TODO-PASTE
$ kubectl config current-context
TODO-PASTE
$ kubectl get nodes
TODO-PASTE
$ docker ps --filter name=dso202-gitops --format '{{.Names}}   {{.Ports}}'
TODO-PASTE (must show 30080 mapped)
```

---

## Task 2: Install Argo CD declaratively

```text
$ kubectl kustomize bootstrap/argocd | grep -E '^kind: (Deployment|StatefulSet)$' | sort | uniq -c
TODO-PASTE (6 Deployment, 1 StatefulSet)
$ kubectl kustomize bootstrap/argocd | grep 'image:' | sort -u
TODO-PASTE (dex, redis from public.ecr.aws, argocd v3.5.6)
```

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
TODO-PASTE (last few lines are enough)
$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
TODO-PASTE
$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
TODO-PASTE
$ kubectl get pods -n argocd
TODO-PASTE (7 Running)
$ kubectl get crd | grep argoproj.io
TODO-PASTE (applications, applicationsets, appprojects)
```

```text
$ kubectl get configmap argocd-cm -n argocd -o yaml | grep -E 'timeout.reconciliation|accounts.reviewer'
TODO-PASTE
$ argocd version
TODO-PASTE
```

Screenshot: Argo CD UI after signing in as admin.

![Argo CD UI after sign-in](img/task2-argocd-ui.png)

---

## Task 3: AppProjects and the root Application

Whitelist check: the chart renders ConfigMap, Deployment, Job, Service, ServiceAccount and StatefulSet (Task 1.3). The `dso202` whitelist in `argocd/projects/dso202.yaml` names exactly these six kinds. Nothing was added; no comment for an addition was needed.

```text
$ kubectl apply -f bootstrap/root
TODO-PASTE
$ kubectl get appproject,application -n argocd
TODO-PASTE
$ argocd app get root
TODO-PASTE (dso202 AppProject must be in the resource list)
$ argocd proj get dso202
TODO-PASTE
```

Screenshot: resource tree of the root Application.

![root resource tree](img/task3-root-tree.png)

---

## Task 4: Platform layer and Sealed Secrets

### 4.1 Controller installed through Git

```text
$ kubectl get applications -n argocd
TODO-PASTE
$ kubectl get pods -n sealed-secrets
TODO-PASTE
$ kubectl get crd sealedsecrets.bitnami.com
TODO-PASTE
```

### 4.2 Sealing key backup (existence and permissions only)

```text
$ ls -l ../dso202-keys/
TODO-PASTE (-rw------- ... sealing-key.backup.yaml)
```

### 4.3 Platform delivered

```text
$ kubectl get applications -n argocd
TODO-PASTE (platform-dev and platform-staging Synced, Healthy)
$ kubectl get namespaces | grep dso202
TODO-PASTE
$ kubectl get sealedsecret -n dso202-dev
TODO-PASTE
$ kubectl describe secret tasktracker-credentials -n dso202-dev
TODO-PASTE (four keys with byte sizes, no values)
$ kubectl describe secret tasktracker-credentials -n dso202-staging
TODO-PASTE
$ kubectl get resourcequota,limitrange -n dso202-dev
TODO-PASTE
$ kubectl get resourcequota,limitrange -n dso202-staging
TODO-PASTE
```

### 4.4 No plaintext in Git

I searched the whole history for each distinct credential value. The values are not written here, only which key was tested.

| Value tested (key name, environment) | `git log -p --all -S'<value>' \| head` output |
|---|---|
| DB_USER / POSTGRES_USER, dev | TODO (empty?) |
| DB_PASSWORD / POSTGRES_PASSWORD, dev | TODO (empty?) |
| DB_USER / POSTGRES_USER, staging | TODO (empty?) |
| DB_PASSWORD / POSTGRES_PASSWORD, staging | TODO (empty?) |

> TODO: only write "(empty)" after you actually ran each search and it printed nothing. If the user name is the same in both environments, say so and test it once.

```text
$ git status --short --ignored
TODO-PASTE (secrets-plain/ should show as ignored, or be gone after deleting the .env files)
```

---

## Task 5: Deliver the workloads to dev and staging

### 5.1 Tag and Applications

```text
$ git tag -a v1.0.0 -m "Baseline release: images 1.0"
$ git push origin v1.0.0
TODO-PASTE
$ git ls-remote --tags origin
TODO-PASTE
```

### 5.2 Wave order in dev

```text
$ kubectl get pods -n dso202-dev -w
TODO-PASTE (database Ready first, then backend created, then frontend, then the smoke-test Pod)
```

> TODO: one or two sentences in your words on what the watch shows, e.g. how many seconds between db Ready and backend created.

### 5.3 Smoke test and dev status

```text
$ kubectl get job -n dso202-dev
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
TODO-PASTE (the JSON list of tasks)
$ argocd app get tasktracker-dev
TODO-PASTE
```

### 5.4 CRUD cycle in dev (http://localhost:30080)

> TODO: create, read, update and delete one task. Either screenshots (one per step) or the browser network tab, as in A1.

### 5.5 Staging and the root Application

Root before the first staging sync:

```text
$ kubectl get applications -n argocd
TODO-PASTE (root Synced but not Healthy; tasktracker-staging OutOfSync / Missing)
$ argocd app get tasktracker-staging
TODO-PASTE
```

```text
$ argocd app sync tasktracker-staging
TODO-PASTE
$ kubectl get svc -n dso202-staging
TODO-PASTE
$ kubectl port-forward -n dso202-staging svc/tasktracker-frontend 8081:8080
```

Root after the first staging sync:

```text
$ kubectl get applications -n argocd
TODO-PASTE (everything Synced and Healthy)
```

Screenshot: tasktracker-dev resource tree.

![tasktracker-dev resource tree](img/task5-dev-tree.png)

---

## Task 6: Access control for Argo CD users

```text
$ argocd account list
TODO-PASTE (admin and reviewer)
$ argocd account update-password --account reviewer
TODO-PASTE (only the success line)
```

```text
$ argocd login localhost:8080 --username reviewer --insecure --name reviewer
$ argocd --argocd-context reviewer app list
TODO-PASTE (only tasktracker-dev and tasktracker-staging)
$ argocd --argocd-context reviewer account can-i get applications 'dso202/tasktracker-dev'
TODO-PASTE (yes)
$ argocd --argocd-context reviewer account can-i sync applications 'dso202/tasktracker-dev'
TODO-PASTE (no)
$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
TODO-PASTE (no)
$ argocd --argocd-context reviewer proj get platform
TODO-PASTE (permission denied)
```

Logs rule added by commit (`git log --oneline -1 -- bootstrap/argocd/argocd-rbac-cm-patch.yaml`):

```text
TODO-PASTE
```

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
TODO-PASTE
$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
TODO-PASTE (yes)
```

Screenshot: private window signed in as reviewer, Pod logs visible.

![reviewer sees logs](img/task6-reviewer-logs.png)

---

## Task 7: A release, a faulty release, and recovery

### 7.1 Pull requests

| # | Title | Merged as |
|---|---|---|
| TODO | TODO | squash |

### 7.2 Part A: frontend 1.1, promoted through the gate

```text
$ argocd app get tasktracker-dev
TODO-PASTE
$ argocd app history tasktracker-dev
TODO-PASTE
```

> TODO: say what the page header at http://localhost:30080 shows now (screenshot optional).

After the PR moving staging to v1.1.0, before syncing:

```text
$ argocd app get tasktracker-staging
TODO-PASTE (OutOfSync, still old frontend at http://localhost:8081)
$ argocd app sync tasktracker-staging
TODO-PASTE
```

### 7.3 Part B: backend 1.1 fails

Bad commit on main: `TODO-SHA`

Observations without intervening (step 5):

```text
$ kubectl get pods -n dso202-dev -w
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
$ kubectl get applications -n argocd
TODO-PASTE
```

> TODO: write in your words: state of the new backend Pod and the old one; sync status and health; whether the smoke test ran; whether the frontend still responded.

### 7.4 Diagnosis

```text
$ kubectl get pods -n dso202-dev
TODO-PASTE
$ kubectl describe pod <new-backend-pod> -n dso202-dev
TODO-PASTE (Events part is enough)
$ kubectl logs <new-backend-pod> -n dso202-dev
TODO-PASTE
```

The exact log line that says what the new image needs:

```text
TODO-PASTE
```

### 7.5 Rollback refused

```text
$ argocd app rollback tasktracker-dev
TODO-PASTE
```

### 7.6 Recovery by revert

```text
$ git revert <bad-commit-sha>
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE (Synced, Healthy, backend 1.0 again)
```

### 7.7 Fix forward

> TODO: which value was added to `environments/*/values.yaml` under `backend.env`, and why (from the log line above).

```text
$ argocd app get tasktracker-dev
TODO-PASTE (Healthy)
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
TODO-PASTE
```

### 7.8 Fixed release promoted (v1.2.0)

```text
$ argocd app sync tasktracker-staging
TODO-PASTE
$ argocd app history tasktracker-dev
TODO-PASTE
$ argocd app history tasktracker-staging
TODO-PASTE (v1.0.0, v1.1.0, v1.2.0 only; the bad commit never appears)
$ git log --oneline --graph --decorate -n 15
TODO-PASTE
```

---

## Task 8: Drift, pruning and project guardrails

Predictions were written before running anything.

### Drill 1: drift in dev

**Prediction:** Argo CD will put the backend back to 1 replica within a few seconds, because tasktracker-dev has `selfHeal: true` and the replica count in Git is 1.

```text
$ kubectl get deployment -n dso202-dev
TODO-PASTE
$ kubectl scale deployment/tasktracker-backend -n dso202-dev --replicas=3
$ kubectl get deployment/tasktracker-backend -n dso202-dev -w
TODO-PASTE
```

**Observation and explanation:** TODO (did it go 1 to 3 and back to 1? how long did it take? which setting explains it: selfHeal, principle 4)

### Drill 2: drift in staging

**Prediction:** Staging will keep 3 replicas. Argo CD will only report the Application as OutOfSync and show the replica difference in the diff, because tasktracker-staging has no automated sync. A manual sync will put it back to 1.

```text
$ kubectl scale deployment/tasktracker-backend -n dso202-staging --replicas=3
$ argocd app get tasktracker-staging
TODO-PASTE
$ argocd app diff tasktracker-staging
TODO-PASTE
$ argocd app sync tasktracker-staging
TODO-PASTE
```

**Observation and explanation:** TODO

### Drill 3: removing a file prunes the object

**Prediction:** The ConfigMap `prune-drill` will appear in dso202-dev about a minute after the push, and will be deleted about a minute after the file is removed from Git, because platform-dev has `prune: true`. The namespace is not affected by this, and even deleting `namespace.yaml` would not delete it because of `Prune=false`.

```text
$ kubectl get configmap prune-drill -n dso202-dev        # after adding the file
TODO-PASTE
$ kubectl get configmap prune-drill -n dso202-dev        # after git rm
TODO-PASTE (NotFound)
```

**Observation and explanation:** TODO (also explain the Prune=false protection on the namespace in one or two sentences; it is not tested)

### Drill 4: the project rejects a kind it does not permit

**Prediction:** The sync of tasktracker-dev will fail with a message that ResourceQuota is not permitted in project dso202, and nothing new will be created in dso202-dev. Staging will not change, because it reads the chart at tag v1.2.0, which does not contain the new template.

```text
$ argocd app get tasktracker-dev
TODO-PASTE (exact message)
$ kubectl get applications -n argocd
TODO-PASTE
$ git revert <commit-sha>
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE (Synced, Healthy again)
```

**Observation and explanation:** TODO

---

## Task 9: Rebuild from Git

```text
$ git rev-parse HEAD
TODO-PASTE
$ kubectl get applications -n argocd        # before
TODO-PASTE
$ date
TODO-PASTE (start)
$ kind delete cluster --name dso202-gitops
$ kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
TODO-PASTE
$ kubectl create namespace sealed-secrets
$ kubectl apply -f ../dso202-keys/sealing-key.backup.yaml
TODO-PASTE
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
$ kubectl apply -f bootstrap/root
TODO-PASTE
$ kubectl get applications -n argocd -w
TODO-PASTE
```

Order in which the Applications became Healthy, with times:

| Application | Healthy at |
|---|---|
| TODO | TODO |

```text
$ argocd admin initial-password -n argocd
(not pasted)
$ argocd login localhost:8080 --username admin --insecure
$ argocd app sync tasktracker-staging
TODO-PASTE
$ argocd app get tasktracker-staging        # same tag as before the rebuild
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-staging
TODO-PASTE
$ date
TODO-PASTE (end)
```

> TODO: one task created in each environment (screenshot or network tab), and the total time from `kind create cluster` to a working dev frontend.

```text
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ../dso202-keys/sealing-key.backup.yaml
$ ls -l ../dso202-keys/
TODO-PASTE
```
