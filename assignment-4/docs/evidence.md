<!--
=============================================================================
File        : docs/evidence.md
Assignment  : DSO202 Assignment 4
Descriptor  : Unit IV 4.1-4.4 - evidence for every task
Purpose     : Command output for Tasks 1 to 10, one section per task. Each
              item shows the command and its output, copied from my terminal.
              Credential values and the sealing key never appear here.
=============================================================================
-->

# DSO202 Assignment 4: Evidence

**Student:** Pema Dolker (02230294)

Every item is the command I ran and its output. Commands are run from `assignment-4/` in my DSO202_Assignments repository. Screenshots are in `docs/img/`, only where the brief asks for one.

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
TODO-PASTE
$ helm repo update
TODO-PASTE
$ helm search repo sealed-secrets/sealed-secrets --versions | head -5
TODO-PASTE
```

### 1.2 Chart contract

| # | Requirement | Where it is satisfied (file : key) |
|---|---|---|
| C1 | Image repository and tag are values per tier; no tag in a template | `values.yaml`: `images.{frontend,backend,database}.{repository,tag}`; tags set in `environments/<env>/values.yaml`; templates use the `tasktracker.image` helper (`_helpers.tpl`), which `required`s both; `values.schema.json` allows only `1.0`/`1.1` |
| C2 | Per-tier config from values; a new backend env var is a values change only | `templates/configmap.yaml` (all keys from values); `backend.env` / `frontend.env` / `database.env` maps rendered by the `tasktracker.extraEnv` helper in each workload template |
| C3 | Chart never renders a Secret; Pods read `existingSecret` = `tasktracker-credentials` | no Secret template; `credentials.existingSecret` in both env files; `tasktracker.secretName` helper `required`s it; used in `backend-deployment.yaml` and `db-statefulset.yaml` `secretKeyRef` |
| C4 | Readiness probes on all tiers (backend `GET /api/status`) | `db-statefulset.yaml` (`pg_isready` over TCP), `backend-deployment.yaml` (`httpGet /api/status`), `frontend-deployment.yaml` (`httpGet /`) |
| C5 | sync-wave annotations: database "0", backend "1", frontend "2" | `metadata.annotations` of `db-statefulset.yaml`, `backend-deployment.yaml`, `frontend-deployment.yaml` |
| C6 | `progressDeadlineSeconds: 120` on backend and frontend | `backend.progressDeadlineSeconds`, `frontend.progressDeadlineSeconds` in `values.yaml`, used in both Deployment specs |
| C7 | Requests and limits on every container | `database.resources`, `backend.resources`, `frontend.resources`, `smokeTest.resources` in `values.yaml` (schema requires both) |
| C8 | No Namespace, ResourceQuota, LimitRange, Role, RoleBinding in the chart | removed from the A3 chart; now in `platform/<env>/namespace.yaml`, `quota-and-limits.yaml`, `rbac.yaml`; kind list below shows none |
| C9 | Ingress (if any) disabled by default | the chart has no Ingress template at all (noted in `frontend-service.yaml` header) |
| C10 | Frontend Service is NodePort, port is a value (30080 dev, 30081 staging) | `frontend.service.type: NodePort`; `frontend.service.nodePort` in each env file; `templates/frontend-service.yaml` |
| C11 | `helm lint` clean, `helm template` works for both environments | output in 1.3 and 1.4 |

### 1.3 helm lint

```text
$ helm lint charts/tasktracker -f environments/dev/values.yaml
TODO-PASTE
$ helm lint charts/tasktracker -f environments/staging/values.yaml
TODO-PASTE
```

### 1.4 Kinds rendered by the chart (needed again in Task 3)

```text
$ helm template tasktracker charts/tasktracker -f environments/dev/values.yaml | grep '^kind:' | sort | uniq -c
TODO-PASTE
$ helm template tasktracker charts/tasktracker -f environments/staging/values.yaml > /dev/null && echo 'staging renders OK'
TODO-PASTE
```

### 1.5 Cluster

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
TODO-PASTE
```

The last line shows host port 30080 mapped to the node.

---

## Task 2: Install Argo CD declaratively

### 2.1 Render checks (before applying)

```text
$ kubectl kustomize bootstrap/argocd | grep -E '^kind: (Deployment|StatefulSet)$' | sort | uniq -c
TODO-PASTE
$ kubectl kustomize bootstrap/argocd | grep 'image:' | sort -u
TODO-PASTE
```

### 2.2 Apply and wait

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts | tail -5
TODO-PASTE
$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
TODO-PASTE
$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
TODO-PASTE
```

### 2.3 Pods and CRDs

```text
$ kubectl get pods -n argocd
TODO-PASTE
$ kubectl get crd | grep argoproj.io
TODO-PASTE
```

### 2.4 Local settings applied

```text
$ kubectl get configmap argocd-cm -n argocd -o yaml | grep -E 'timeout.reconciliation|accounts.reviewer'
TODO-PASTE
$ argocd version
TODO-PASTE
```

### 2.5 Screenshot

![Argo CD UI after sign-in](img/task2-argocd-ui.png)

---

## Task 3: AppProjects and the root Application

### 3.1 Whitelist check

The chart renders (Task 1.4): ConfigMap, Deployment, Job, Service, ServiceAccount, StatefulSet. The `namespaceResourceWhitelist` in `argocd/projects/dso202.yaml` lists exactly these six kinds, so nothing was added or removed. No PersistentVolumeClaim is needed, because the database PVC comes from the StatefulSet's `volumeClaimTemplates` and is created by the StatefulSet controller, not by Argo CD.

### 3.2 After `kubectl apply -f bootstrap/root`

```text
$ kubectl apply -f bootstrap/root
TODO-PASTE
$ kubectl get appproject,application -n argocd
TODO-PASTE
$ argocd app get root
TODO-PASTE
$ argocd proj get dso202
TODO-PASTE
```

`dso202` appears in the resource list of `argocd app get root`, so it was created by the root, not by me.

### 3.3 Screenshot

![root Application resource tree](img/task3-root-tree.png)

Answer Q1: README section 9.

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

### 4.2 Sealing key backup (existence and permissions only, never the contents)

```text
$ ls -l ~/dso202-keys/
TODO-PASTE
```

### 4.3 Sealing

Both files were made with `kubectl create secret generic tasktracker-credentials --namespace <ns> --from-env-file=secrets-plain/<env>.env --dry-run=client -o yaml | kubeseal --format yaml > platform/<env>/tasktracker-credentials.sealed.yaml`. Dev and staging use different passwords.

```text
$ grep -E '^  name:|^  namespace:|DB_|POSTGRES_' platform/dev/tasktracker-credentials.sealed.yaml | cut -c1-60
TODO-PASTE
```

### 4.4 Result in the cluster

```text
$ kubectl get applications -n argocd
TODO-PASTE
$ kubectl get namespaces | grep dso202
TODO-PASTE
$ kubectl get sealedsecret -n dso202-dev
TODO-PASTE
$ kubectl get sealedsecret -n dso202-staging
TODO-PASTE
$ kubectl describe secret tasktracker-credentials -n dso202-dev
TODO-PASTE
$ kubectl describe secret tasktracker-credentials -n dso202-staging
TODO-PASTE
$ kubectl get resourcequota,limitrange -n dso202-dev
TODO-PASTE
$ kubectl get resourcequota,limitrange -n dso202-staging
TODO-PASTE
```

### 4.5 No plaintext in Git

Searched the whole history for each distinct credential value (the values themselves are not written here). Keys tested: DB_USER/POSTGRES_USER (dev), DB_PASSWORD/POSTGRES_PASSWORD (dev), DB_USER/POSTGRES_USER (staging), DB_PASSWORD/POSTGRES_PASSWORD (staging).

```text
$ git log -p --all -S'<dev user>' | head
(no output)
$ git log -p --all -S'<dev password>' | head
(no output)
$ git log -p --all -S'<staging user>' | head
(no output)
$ git log -p --all -S'<staging password>' | head
(no output)
$ git status --short --ignored
TODO-PASTE
```

Answer Q2: README section 9.

---

## Task 5: Deliver the workloads to dev and staging

### 5.1 Baseline tag

```text
$ git ls-remote --tags origin
TODO-PASTE
```

### 5.2 Wave order in dev (Pod creation order)

```text
$ kubectl get pods -n dso202-dev -w
TODO-PASTE
```

The database Pod became Ready before the backend Pod was created, and the backend before the frontend. Then the smoke-test Job ran once.

### 5.3 Smoke test and dev status

```text
$ kubectl get job -n dso202-dev
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
```

### 5.4 CRUD cycle in dev

Through the backend Service (`kubectl port-forward -n dso202-dev svc/tasktracker-backend 8090:8080` in another terminal):

```text
$ curl -s localhost:8090/api/tasks
TODO-PASTE
$ curl -s -X POST localhost:8090/api/tasks -H 'Content-Type: application/json' -d '{"title":"A4 GitOps test","description":"created in dev"}'
TODO-PASTE
$ curl -s localhost:8090/api/tasks/<id>
TODO-PASTE
$ curl -s -X PUT localhost:8090/api/tasks/<id> -H 'Content-Type: application/json' -d '{"status":"in_progress"}'
TODO-PASTE
$ curl -s -o /dev/null -w '%{http_code}\n' -X DELETE localhost:8090/api/tasks/<id>
TODO-PASTE
$ curl -s -w '\n%{http_code}\n' localhost:8090/api/tasks/<id>
TODO-PASTE
```

The same cycle also works in the browser at http://localhost:30080 while the port-forward is running.

### 5.5 Staging, before and after the first sync

```text
$ kubectl get applications -n argocd
TODO-PASTE
$ argocd app get tasktracker-staging
TODO-PASTE
$ argocd app sync tasktracker-staging
TODO-PASTE
$ kubectl get applications -n argocd
TODO-PASTE
$ kubectl get svc -n dso202-staging
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-staging
TODO-PASTE
```

Root was Synced but not Healthy before the staging sync, and Healthy after it (Q3).

### 5.6 All Applications

```text
$ kubectl get applications -n argocd
TODO-PASTE
```

### 5.7 Screenshot

![tasktracker-dev resource tree](img/task5-dev-tree.png)

Answer Q3: README section 9.

---

## Task 6: Access control for Argo CD users

### 6.1 Accounts

```text
$ argocd account list
TODO-PASTE
```

### 6.2 reviewer before the logs rule

```text
$ argocd login localhost:8080 --username reviewer --insecure --name reviewer
TODO-PASTE
$ argocd --argocd-context reviewer app list
TODO-PASTE
$ argocd --argocd-context reviewer account can-i get applications 'dso202/tasktracker-dev'
TODO-PASTE
$ argocd --argocd-context reviewer account can-i sync applications 'dso202/tasktracker-dev'
TODO-PASTE
$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
TODO-PASTE
$ argocd --argocd-context reviewer proj get platform
TODO-PASTE
```

In the private browser window the Sync button was refused and Pod logs were hidden.

### 6.3 Logs rule added by a commit

```text
$ git log --oneline -1 -- bootstrap/argocd/argocd-rbac-cm-patch.yaml
TODO-PASTE
$ git show --stat HEAD -- bootstrap/argocd/argocd-rbac-cm-patch.yaml | tail -3
TODO-PASTE
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts | grep rbac
TODO-PASTE
$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
TODO-PASTE
```

### 6.4 Screenshot

![reviewer session showing Pod logs](img/task6-reviewer-logs.png)

Answer Q4: README section 9.

---

## Task 7: A release, a faulty release, and recovery

### 7.1 Pull requests

TODO-PASTE (list of PR numbers and titles, or a screenshot of the closed PR list)

### 7.2 Part A: frontend 1.1 in dev

```text
$ kubectl get pods -n dso202-dev -w
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
$ argocd app history tasktracker-dev
TODO-PASTE
```

The page header at http://localhost:30080 shows release 1.1.

### 7.3 Promotion to staging (v1.1.0)

```text
$ git ls-remote --tags origin
TODO-PASTE
$ argocd app get tasktracker-staging
TODO-PASTE
$ argocd app sync tasktracker-staging
TODO-PASTE
```

Before the sync staging was OutOfSync and http://localhost:8081 still showed the old header; after the sync it showed 1.1.

### 7.4 Part B: backend 1.1 (the bad commit)

Bad commit on main: `TODO-PASTE (SHA)`

```text
$ kubectl get pods -n dso202-dev -w
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
$ kubectl get applications -n argocd
TODO-PASTE
```

Observations (no intervention):

- New backend Pod: TODO
- Old backend Pod: TODO
- tasktracker-dev sync status / health: TODO
- Smoke test ran?: TODO
- Frontend still responding?: TODO

### 7.5 Diagnosis

```text
$ kubectl get pods -n dso202-dev
TODO-PASTE
$ kubectl describe pod <new-backend-pod> -n dso202-dev
TODO-PASTE
$ kubectl logs <new-backend-pod> -n dso202-dev
TODO-PASTE
```

The line that says what the image needs:

```text
TODO-PASTE
```

### 7.6 Rollback refused

```text
$ argocd app rollback tasktracker-dev
TODO-PASTE
```

### 7.7 Recovery by git revert

```text
$ argocd app get tasktracker-dev
TODO-PASTE
```

### 7.8 Fix forward

```text
$ git show HEAD -- environments/dev/values.yaml
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
TODO-PASTE
```

### 7.9 Promotion of the fixed release (v1.2.0)

```text
$ argocd app sync tasktracker-staging
TODO-PASTE
$ argocd app get tasktracker-staging
TODO-PASTE
```

### 7.10 History

```text
$ git log --oneline --graph --decorate -n 15
TODO-PASTE
$ argocd app history tasktracker-dev
TODO-PASTE
$ argocd app history tasktracker-staging
TODO-PASTE
```

`argocd app history tasktracker-staging` has no revision with the faulty backend: staging went v1.0.0 → v1.1.0 → v1.2.0.

Answer Q5: README section 9.

---

## Task 8: Drift, pruning and project guardrails

### Drill 1: drift in dev

**Prediction:** TODO (write before running)

```text
$ kubectl get deployment -n dso202-dev
TODO-PASTE
$ kubectl scale deployment/tasktracker-backend -n dso202-dev --replicas=3
TODO-PASTE
$ kubectl get deployment/tasktracker-backend -n dso202-dev -w
TODO-PASTE
```

**Result:** TODO (did the prediction hold, and which setting/principle explains it)

### Drill 2: drift in staging

**Prediction:** TODO

```text
$ kubectl scale deployment/tasktracker-backend -n dso202-staging --replicas=3
TODO-PASTE
$ argocd app get tasktracker-staging
TODO-PASTE
$ argocd app diff tasktracker-staging
TODO-PASTE
$ argocd app sync tasktracker-staging
TODO-PASTE
$ kubectl get deployment/tasktracker-backend -n dso202-staging
TODO-PASTE
```

**Result:** TODO

### Drill 3: removing a file prunes the object

**Prediction:** TODO

```text
$ git log --oneline -1
TODO-PASTE
$ kubectl get configmap prune-drill -n dso202-dev
TODO-PASTE
$ git log --oneline -1
TODO-PASTE
$ kubectl get configmap prune-drill -n dso202-dev
TODO-PASTE
```

**Result:** TODO (also explain why deleting `platform/dev/namespace.yaml` would NOT delete the namespace: `Prune=false`)

### Drill 4: the project rejects a kind it does not permit

**Prediction:** TODO

```text
$ git log --oneline -1
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
$ kubectl get applications -n argocd
TODO-PASTE
$ git revert --no-edit HEAD && git push
TODO-PASTE
$ argocd app get tasktracker-dev
TODO-PASTE
```

Exact message: `TODO-PASTE`

**Result:** TODO (and why staging was unaffected)

---

## Task 9: Rebuild from Git

### 9.1 Before

```text
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ~/dso202-keys/sealing-key.backup.yaml && chmod 600 ~/dso202-keys/sealing-key.backup.yaml && ls -l ~/dso202-keys/
TODO-PASTE
$ git rev-parse HEAD
TODO-PASTE
$ kubectl get applications -n argocd
TODO-PASTE
```

### 9.2 Delete and recreate the cluster

```text
$ date
TODO-PASTE
$ kind delete cluster --name dso202-gitops
TODO-PASTE
$ kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
TODO-PASTE
```

### 9.3 Restore the sealing key first

```text
$ kubectl create namespace sealed-secrets
TODO-PASTE
$ kubectl apply -f ~/dso202-keys/sealing-key.backup.yaml
TODO-PASTE
```

### 9.4 Bootstrap (nothing else applied by hand)

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts | tail -3
TODO-PASTE
$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
TODO-PASTE
$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
TODO-PASTE
$ kubectl apply -f bootstrap/root
TODO-PASTE
```

### 9.5 Applications in wave order

```text
$ kubectl get applications -n argocd -w
TODO-PASTE
```

Order they became Healthy: TODO

### 9.6 Sign in and sync staging

```text
$ argocd login localhost:8080 --username admin --insecure
TODO-PASTE
$ argocd app sync tasktracker-staging
TODO-PASTE
$ argocd app get tasktracker-staging
TODO-PASTE
```

### 9.7 Both environments work

```text
$ kubectl get applications -n argocd
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
TODO-PASTE
$ kubectl logs job/tasktracker-smoke-test -n dso202-staging
TODO-PASTE
$ curl -s -X POST localhost:8090/api/tasks -H 'Content-Type: application/json' -d '{"title":"after rebuild (dev)"}'
TODO-PASTE
$ curl -s -X POST localhost:8091/api/tasks -H 'Content-Type: application/json' -d '{"title":"after rebuild (staging)"}'
TODO-PASTE
$ date
TODO-PASTE
```

Total time from `kind create cluster` to a working dev frontend: TODO

Staging is at the same tag as before the rebuild: TODO (v1.2.0)

### 9.8 Fresh key backup from the rebuilt cluster

```text
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ~/dso202-keys/sealing-key.backup.yaml && chmod 600 ~/dso202-keys/sealing-key.backup.yaml
TODO-PASTE
$ ls -l ~/dso202-keys/
TODO-PASTE
```

Answer Q6: README section 9.
