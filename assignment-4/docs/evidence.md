<!--
=============================================================================
File        : docs/evidence.md
Assignment  : DSO202 Assignment 4
Descriptor  : Unit IV 4.1-4.4 - evidence for every task
Purpose     : Command output for every task, one section per task. Each item
              shows the command and its output, copied from my terminal.
              Credential values and the sealing key never appear here.
=============================================================================
-->

# DSO202 Assignment 4: Evidence

**Student:** Pema Dolker (02230294)

Every item is the command I ran and its output. Commands are run from `assignment-4/` in my DSO202_Assignments repository. Screenshots are in `docs/img/`, only where the brief asks for one.

---

## Task 1: Repository, chart contract and cluster

### 1.1 Tool check (section 3.2)

<!-- AUTO:t1-tools -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t1-tools -->

<!-- AUTO:t1-helmrepo -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t1-helmrepo -->

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
| C8 | No Namespace, ResourceQuota, LimitRange, Role, RoleBinding in the chart | removed from the A3 chart; now in `platform/<env>/namespace.yaml`, `quota-and-limits.yaml`, `rbac.yaml`; the kind list below shows none |
| C9 | Ingress (if any) disabled by default | the chart has no Ingress template at all (noted in the `frontend-service.yaml` header) |
| C10 | Frontend Service is NodePort, port is a value (30080 dev, 30081 staging) | `frontend.service.type: NodePort`; `frontend.service.nodePort` in each env file; `templates/frontend-service.yaml` |
| C11 | `helm lint` clean, `helm template` works for both environments | output in 1.3 and 1.4 |

### 1.3 helm lint

<!-- AUTO:t1-lint -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t1-lint -->

### 1.4 Kinds rendered by the chart (used again in Task 3)

<!-- AUTO:t1-kinds -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t1-kinds -->

### 1.5 Cluster

<!-- AUTO:t1-cluster -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t1-cluster -->

The `docker ps` line shows host port 30080 mapped to the node.

---

## Task 2: Install Argo CD declaratively

### 2.1 Render checks (before applying)

<!-- AUTO:t2-render -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t2-render -->

### 2.2 Apply and wait

<!-- AUTO:t2-apply -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t2-apply -->

### 2.3 Pods and CRDs

<!-- AUTO:t2-pods -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t2-pods -->

### 2.4 Local settings applied

<!-- AUTO:t2-settings -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t2-settings -->

### 2.5 Screenshot

![Argo CD UI after sign-in](img/task2-argocd-ui.png)

---

## Task 3: AppProjects and the root Application

### 3.1 Whitelist check

The chart renders (1.4): ConfigMap, Deployment, Job, Service, ServiceAccount, StatefulSet. The `namespaceResourceWhitelist` in `argocd/projects/dso202.yaml` lists exactly these six kinds, so nothing was added or removed. No PersistentVolumeClaim is needed, because the database PVC comes from the StatefulSet's `volumeClaimTemplates` and is created by the StatefulSet controller, not by Argo CD.

### 3.2 After applying bootstrap/root

<!-- AUTO:t3-apply -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t3-apply -->

`dso202` appears in the resource list of `argocd app get root`, so it was created by the root, not by me.

### 3.3 Screenshot

![root Application resource tree](img/task3-root-tree.png)

Answer Q1: README section 9.

---

## Task 4: Platform layer and Sealed Secrets

### 4.1 Controller installed through Git

<!-- AUTO:t4-controller -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t4-controller -->

### 4.2 Sealing key backup (existence and permissions only, never the contents)

<!-- AUTO:t4-backup -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t4-backup -->

### 4.3 Sealed files

Both files were made with `kubectl create secret generic tasktracker-credentials --namespace <ns> --from-env-file=secrets-plain/<env>.env --dry-run=client -o yaml | kubeseal --format yaml`. Dev and staging use different passwords. Only the start of each ciphertext is shown.

<!-- AUTO:t4-sealed -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t4-sealed -->

### 4.4 Result in the cluster

<!-- AUTO:t4-result -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t4-result -->

### 4.5 No plaintext in Git

Every distinct credential value was searched for in the whole history with `git log -p --all -S'<value>'`. The values themselves are not written here.

<!-- AUTO:t4-history -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t4-history -->

Answer Q2: README section 9.

---

## Task 5: Deliver the workloads to dev and staging

### 5.1 Baseline tag

<!-- AUTO:t5-tag -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t5-tag -->

### 5.2 Wave order in dev

Pod events recorded with a timestamp while dev synced for the first time:

<!-- AUTO:t5-waves -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t5-waves -->

### 5.3 Smoke test and dev status

<!-- AUTO:t5-smoke -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t5-smoke -->

### 5.4 CRUD cycle in dev

Through the backend Service (port-forward on 8090, the same address the dev frontend's `BACKEND_URL` uses):

<!-- AUTO:t5-crud -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t5-crud -->

### 5.5 Staging, before and after the first sync

<!-- AUTO:t5-staging -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t5-staging -->

### 5.6 All Applications

<!-- AUTO:t5-apps -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t5-apps -->

### 5.7 Screenshots

![tasktracker-dev resource tree](img/task5-dev-tree.png)

![dev frontend at localhost:30080](img/task5-dev-frontend.png)

Answer Q3: README section 9.

---

## Task 6: Access control for Argo CD users

### 6.1 Accounts

<!-- AUTO:t6-accounts -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t6-accounts -->

### 6.2 reviewer before the logs rule

<!-- AUTO:t6-before -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t6-before -->

In the private browser window the Sync button was refused and Pod logs were hidden.

### 6.3 Logs rule added by a commit

<!-- AUTO:t6-logs -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t6-logs -->

### 6.4 Screenshot

![reviewer session showing Pod logs](img/task6-reviewer-logs.png)

Answer Q4: README section 9.

---

## Task 7: A release, a faulty release, and recovery

TODO: Task 7 is waiting for the tutor's 1.1 images.

---

## Task 8: Drift, pruning and project guardrails

### Drill 1: drift in dev is reverted

<!-- AUTO:d1 -->
_(filled in by run-a4.sh)_
<!-- /AUTO:d1 -->

### Drill 2: drift in staging is reported, not reverted

<!-- AUTO:d2 -->
_(filled in by run-a4.sh)_
<!-- /AUTO:d2 -->

### Drill 3: removing a file prunes the object

<!-- AUTO:d3 -->
_(filled in by run-a4.sh)_
<!-- /AUTO:d3 -->

### Drill 4: the project rejects a kind it does not permit

<!-- AUTO:d4 -->
_(filled in by run-a4.sh)_
<!-- /AUTO:d4 -->

---

## Task 9: Rebuild from Git

### 9.1 Before

<!-- AUTO:t9-before -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-before -->

### 9.2 Delete and recreate the cluster

<!-- AUTO:t9-cluster -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-cluster -->

### 9.3 Restore the sealing key first

<!-- AUTO:t9-key -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-key -->

### 9.4 Bootstrap (nothing else applied by hand)

<!-- AUTO:t9-bootstrap -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-bootstrap -->

### 9.5 Applications coming up in wave order

<!-- AUTO:t9-waves -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-waves -->

### 9.6 Sign in and sync staging

<!-- AUTO:t9-staging -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-staging -->

### 9.7 Both environments work

<!-- AUTO:t9-verify -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-verify -->

### 9.8 Fresh key backup from the rebuilt cluster

<!-- AUTO:t9-backup -->
_(filled in by run-a4.sh)_
<!-- /AUTO:t9-backup -->

Answer Q6: README section 9.
