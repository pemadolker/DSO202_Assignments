# DSO202 Assignment 4: GitOps Delivery of the Task Tracker with Argo CD

**Student:** Pema Dolker  
**Student ID:** 02230294  
**Module:** DSO202: Scaling, Orchestration, Monitoring & Observability  
<!-- **Repository:** https://github.com/pemadolker/dso202-gitops -->

## Table of Contents

1. Purpose
2. Repository layout
3. Pinned versions
4. How the pieces fit together
5. Changes to the Assignment 3 chart
6. How credentials are handled
7. Building the whole environment from an empty machine
8. Cleanup
9. Written answers (Q1 to Q6)
10. Problems I ran into
11. References

<!-- The command output for every task is in [docs/evidence.md](docs/evidence.md). -->

## 1. Purpose

In Assignments 1 to 3 the Task Tracker (nginx frontend, Node.js backend, PostgreSQL) only reached the cluster because I ran `kubectl apply` or `helm install` myself. In this assignment that step is removed. Argo CD runs inside the cluster, reads this repository, and makes the cluster match it. After the bootstrap (installing Argo CD and creating one root Application), every change to the cluster is a commit to this repository.

The repository delivers the Task Tracker to two environments:

- **dev** follows the `main` branch and syncs automatically, with prune and self-heal. Every merge is deployed within about a minute.
- **staging** follows a Git tag and only changes when a person moves the tag in Git and presses sync. It is the gate between dev and anything after it.

No application code is written. The images are the ones from the earlier assignments.

## 2. Repository layout

```text
dso202-gitops/
├── README.md
├── .gitignore                         first commit, before anything else
├── cluster/kind-cluster.yaml          kind cluster, host port 30080 mapped
├── bootstrap/                         applied by hand, once per cluster
│   ├── argocd/                        Argo CD v3.5.6 + local settings (Kustomize)
│   └── root/                          platform AppProject + root Application
├── argocd/                            watched by the root Application
│   ├── projects/dso202.yaml           workload AppProject
│   └── applications/                  sealed-secrets, platform-dev/staging, tasktracker-dev/staging
├── platform/                          plain manifests per environment
│   ├── dev/                           namespace, quota and limits, RBAC, sealed credentials
│   └── staging/
├── charts/tasktracker/                the A3 chart, changed for GitOps
├── environments/
│   ├── dev/values.yaml                only what differs in dev
│   └── staging/values.yaml            only what differs in staging
└── docs/evidence.md
```

Each directory has one job. Bootstrap files, Argo CD objects, platform objects, the chart and the environment values never share a directory. Every file starts with a header that gives its path, the assignment, the descriptor section and what it is for.

## 3. Pinned versions

| Component | Version | Where it is pinned |
|---|---|---|
| Argo CD (server and `argocd` CLI) | v3.5.6 | URL in `bootstrap/argocd/kustomization.yaml` |
| Sealed Secrets Helm chart | 2.20.0 | `targetRevision` in `argocd/applications/sealed-secrets.yaml` |
| Sealed Secrets controller | 0.40.0 | installed by chart 2.20.0 |
| kubeseal CLI | v0.40.0 | installed on the laptop, matches the controller |
| Task Tracker images | 1.0 (baseline), 1.1 (release) | `environments/<env>/values.yaml` |
| Smoke test image | busybox:1.37 | `charts/tasktracker/templates/smoke-test-job.yaml` |
| Staging revision | Git tag (v1.0.0, then v1.1.0, then v1.2.0) | `argocd/applications/tasktracker-staging.yaml` |
| kind, node image, kubectl | as in Practical 1 | see the tool check in evidence, Task 1 |
| Helm | as in Assignment 3 | see the tool check in evidence, Task 1 |

The words `latest`, `stable`, `master` and `HEAD` are not used as a version anywhere. The chart's values schema also rejects them as image tags, so `helm lint` fails if one is typed by mistake.

The images are `pdolker/dso202-*`, my amd64 rebuilds of the tutor images. As in Assignments 1 to 3, this was approved by the tutor because the tutor images are published for arm64 only. The repository is a value in the chart (`images.<tier>.repository`), so switching to `sarojsanyasi/*` is a values change only. The same arrangement was used for the 1.1 release images in Task 7, and I confirmed it with the lecturer before starting this assignment.

## 4. How the pieces fit together

```text
kind cluster "dso202-gitops"
├── argocd            Argo CD (7 Pods), polls GitHub every 60 s
├── sealed-secrets    Sealed Secrets controller, holds the sealing key
├── dso202-dev        Task Tracker, branch main, automated sync
└── dso202-staging    Task Tracker, Git tag, manual sync
```

### 4.1 What is applied by hand and what comes from Git

Only two things are applied by hand: `bootstrap/argocd` (Argo CD itself) and `bootstrap/root` (the `platform` project and the `root` Application). Everything else is a file under `argocd/` that the root Application creates. The order is set with sync waves on the child objects:

| Wave | Object | Why it has to be here |
|---|---|---|
| -3 | AppProject `dso202` | The workload Applications refer to it, so it must exist first. |
| -2 | Application `sealed-secrets` | The SealedSecret kind does not exist until the controller and its CRD are installed. |
| -1 | Applications `platform-dev`, `platform-staging` | The namespaces, quotas and decrypted credentials must exist before any Pod starts. |
| 0 | Applications `tasktracker-dev`, `tasktracker-staging` | The workloads, last. |

Waves alone are not enough for this. Since Argo CD 1.8 a parent Application counts its child Applications as Healthy as soon as the objects exist, so the root would not really wait. The Lua health check in `bootstrap/argocd/argocd-cm-patch.yaml` passes each child's real health up to the root, so the root waits for wave -1 to be Healthy before it starts wave 0.

Inside the chart there is a second set of waves: database 0, backend 1, frontend 2, and then the smoke test runs as a PostSync hook. So the database is ready before the backend starts, the backend is ready before the frontend starts, and the Job only runs when all three are Healthy.

### 4.2 Two projects, least privilege

| Project | Used by | May deploy to | May create |
|---|---|---|---|
| `platform` | root, sealed-secrets, platform-dev, platform-staging | argocd, sealed-secrets, dso202-dev, dso202-staging | everything (administrator level) |
| `dso202` | tasktracker-dev, tasktracker-staging | dso202-dev, dso202-staging only | Deployment, StatefulSet, Service, ConfigMap, ServiceAccount, Job. No cluster-scoped kinds. |

The `dso202` whitelist is exactly what the chart renders. I checked it with `helm template ... | grep '^kind:' | sort | uniq -c`, which lists ConfigMap 1, Deployment 2, Job 1, Service 3, ServiceAccount 1 and StatefulSet 1. I did not add or remove anything from the provided list. The database PVC is not needed in the list, because it is created by the StatefulSet controller from `volumeClaimTemplates`, not by Argo CD.

Because the workload project cannot create a Namespace, ResourceQuota, LimitRange, Role, RoleBinding or SealedSecret, a mistake in the chart cannot give the Task Tracker more room or more rights. Drill 4 in Task 8 shows this: a ResourceQuota added to the chart is refused at sync time.

### 4.3 dev and staging

| | dev | staging |
|---|---|---|
| Namespace | dso202-dev | dso202-staging |
| Git revision | `main` (moves) | a tag such as `v1.0.0` (never moves) |
| Sync | automated, prune, self-heal | manual |
| Values file | environments/dev/values.yaml | environments/staging/values.yaml |
| Frontend | NodePort 30080, http://localhost:30080 | NodePort 30081, through `kubectl port-forward` |
| Credentials | SealedSecret in platform/dev | separate SealedSecret in platform/staging, different password |

The chart is the same in both environments. Everything that differs is in the environment values file or in the Application's `targetRevision`. No template checks which environment it is in.

A release is a commit that changes an image tag in the values files. Dev picks it up from `main` straight away. Staging reads both the chart and its values file at the tag, so editing `environments/staging/values.yaml` on `main` changes nothing in staging until someone moves the tag in `tasktracker-staging.yaml` and syncs. That is what I used in Task 7.

## 5. Changes to the Assignment 3 chart

The A3 chart was written for `helm install` by a person. For Argo CD it had to follow the chart contract C1 to C11 in the brief. The full table with the file and key for each requirement is in the evidence file under Task 1. The main changes and my reasons:

**The Secret template is gone (C3).** In A3 the chart could render the database Secret from values, and those values ended up in Helm's release record. Here the chart only refers to a Secret by name (`credentials.existingSecret: tasktracker-credentials`). There is no fallback, so if the name is missing the render fails instead of quietly making something up.

**ResourceQuota and LimitRange moved out (C8).** In A3 they were templates in the chart. Now they are plain files in `platform/<env>/quota-and-limits.yaml`, delivered by the platform Applications. If they stayed in the chart, the workload project would need permission to create quotas, which means a chart commit could raise its own limits.

**The database is a StatefulSet again.** A3 used a Deployment and a PVC (the A1 design). I went back to the A2 StatefulSet, because the whitelist in the brief lists StatefulSet and not PersistentVolumeClaim, and because a StatefulSet's PVC is created by Kubernetes rather than by Argo CD. The update strategy is RollingUpdate, since Argo CD does not report an OnDelete StatefulSet as Healthy and the backend wave would wait forever. I also wrote out `volumeMode: Filesystem` in the claim template, so the object stored in the cluster matches Git and Argo CD does not show a false difference.

**Image tags have no default (C1).** In A3 an empty tag fell back to the chart's `appVersion`. Now the tag must be set in the environment file, otherwise the render fails. A release is then exactly one visible change in a values file.

**Extra environment variables from values (C2).** Each tier has an `env:` map in values that is rendered as plain `env` entries. In Task 7 the fixed backend needed one more variable, and adding it was a values change only, with no template change.

**Readiness probes (C4).** The backend probe is `GET /api/status`, which runs `SELECT 1` against the database, so the backend is only Ready when it can actually reach PostgreSQL. The database uses `pg_isready` over TCP, and the frontend uses `GET /`. In A1 I wrote that the backend did not need probes because it just retries until the database is up. That was fine for a person running `kubectl apply`, but sync waves only work if "Healthy" means "really ready", so here the probes are needed.

**Sync waves and progress deadline (C5, C6).** Database "0", backend "1", frontend "2" on the workloads. Backend and frontend have `progressDeadlineSeconds: 120`, so a broken rollout is reported as Degraded after two minutes instead of ten. Task 7 depends on this.

**The frontend NodePort is a value (C10).** 30080 in dev, 30081 in staging. The A2 quota had `services.nodeports: "0"` because the frontend went through the Ingress. There is no ingress controller in this assignment (and the chart has no Ingress template, C9), so I changed that one value to `"1"` in the platform quota.

**The smoke test replaces the Helm tests.** A3 had two `helm test` Pods. Argo CD does not run Helm test hooks, and a Pod is not in the project whitelist, so I removed them. The PostSync smoke-test Job (Listing 13) does the same job. I replaced `backend-svc` in the listing with the Service name rendered by the chart's own helper, so the Job always uses the right name (`tasktracker-backend:8080`) even if the release name changes.

**A ServiceAccount for the backend.** The backend Pods now run under their own ServiceAccount instead of `default`, like `backend-sa` in A2. The backend never calls the Kubernetes API, so the token is not mounted and no Role is bound to it.

`NOTES.txt` and the packaged `.tgz` from A3 were not copied, because nothing reads them when Argo CD renders the chart.

## 6. How credentials are handled

- The database credentials (`DB_USER`, `DB_PASSWORD`, `POSTGRES_USER`, `POSTGRES_PASSWORD`) are only in Git as SealedSecrets: `platform/dev/tasktracker-credentials.sealed.yaml` and `platform/staging/tasktracker-credentials.sealed.yaml`. They are encrypted with the public key of this cluster's Sealed Secrets controller and only that controller can decrypt them.
- Dev and staging have different passwords and are sealed separately. With the default strict scope the name and namespace are part of the encryption, so the dev file cannot be decrypted in staging.
- The plaintext input was typed into `secrets-plain/<env>.env` in an editor, so it never went into the shell history. `kubectl create secret --dry-run=client` piped straight into `kubeseal`, so the plain Secret was never written to disk. The `.env` files were deleted afterwards and the values are kept in my password manager.
- `secrets-plain/`, `*-plain.yaml`, `*.key`, `*sealing-key*` and `*.backup.yaml` are in `.gitignore`, which was the very first commit. I do not rely on that alone: in Task 4 I searched the whole Git history for each credential value and found nothing (evidence, Task 4).
- The sealing key backup is in `../dso202-keys/` next to the repository, with permission 600. It is the only piece of state that is not in Git and cannot be recreated. It was backed up again after the rebuild in Task 9.
- The `Role` in `platform/<env>/rbac.yaml` does not include Secrets, so the read-only ServiceAccount cannot read the decrypted credentials.

## 7. Building the whole environment from an empty machine

This is the sequence I used in Task 9. It needs Docker, kind, kubectl, Helm, git, `argocd` v3.5.6 and `kubeseal` v0.40.0 on the laptop, and the sealing key backup in `../dso202-keys/`.

```bash
# 1. Get the repository and create the cluster
git clone https://github.com/pemadolker/dso202-gitops.git
cd dso202-gitops
kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml

# 2. Put the sealing key back BEFORE the controller exists
kubectl create namespace sealed-secrets
kubectl apply -f ../dso202-keys/sealing-key.backup.yaml

# 3. Install Argo CD from the pinned Kustomize files (server-side apply is required)
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s

# 4. Create the platform project and the root Application; Argo CD does the rest
kubectl apply -f bootstrap/root
kubectl get applications -n argocd -w

# 5. Sign in (port-forward in its own terminal) and sync staging, which is manual
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
argocd app sync tasktracker-staging

# 6. Check both environments
#    dev:     http://localhost:30080
#    staging: kubectl port-forward -n dso202-staging svc/tasktracker-frontend 8081:8080
#             then http://localhost:8081

# 7. Back up the sealing key again from the new cluster
kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ../dso202-keys/sealing-key.backup.yaml
chmod 600 ../dso202-keys/sealing-key.backup.yaml
```

If the restore in step 2 complains about `resourceVersion` or `uid`, those lines (and `creationTimestamp`) have to be removed from each item in the backup file before applying it again.

On a cluster where no backup exists (the very first time), step 2 is skipped. The controller then makes a new key, and both credential files have to be sealed again with `kubeseal` (Task 4 in the evidence) and committed before the platform Applications can become Healthy.

## 8. Cleanup

```bash
# Stop the port-forwards with Ctrl+C, then delete the whole cluster
kind delete cluster --name dso202-gitops

# Remove the argocd CLI contexts for this cluster
argocd context localhost:8080 --delete
argocd context reviewer --delete
```

Deleting the cluster removes everything, including the database data. Deleting only the `root` Application would also remove every child Application and their workloads, because of the finalizers, so it should never be done casually. The sealing key backup in `../dso202-keys/` is kept until it is certain the SealedSecrets in Git will not be needed again.

## 9. Written answers

### Q1. Why is the platform project applied by hand while dso202 is created by the root Application, and what is the risk if dso202 could deploy into the argocd namespace?

The root Application itself lives in the `platform` project (`project: platform` in `root-app.yaml`). An Application can only be created if its project already exists, so the root cannot create the project it belongs to. Something has to exist first, and that is the bootstrap step: the `platform` project and the root are the only two objects I applied by hand. `platform` is also the administrator-level project (every cluster-scoped kind, and the argocd namespace), so it makes sense that it is created once on purpose and is not something a normal merge can reshape.

`dso202` is ordinary configuration. It is created by the root from `argocd/projects/dso202.yaml` in wave -3, so it is versioned and reviewed like everything else, and if someone edits its whitelist in the cluster, self-heal on the root puts it back. In my evidence for Task 3, `dso202` appears in the resource list of `argocd app get root`, which shows it was created by the root and not by me.

If `dso202` were allowed to deploy into the `argocd` namespace, the workload project would effectively be an administrator. Application and AppProject objects are just objects in the argocd namespace, so any Application that can write there can create new Applications in any project, including `platform`, and deploy anything anywhere. It does not even need those kinds in its whitelist: ConfigMap is in the whitelist, so a chart commit could render a ConfigMap called `argocd-rbac-cm` into the argocd namespace with `policy.default: role:admin` and give every user full rights. That is why only the `platform` project lists the argocd namespace as a destination.

### Q2. What does strict scope prevent, and what is lost, and what must be done, if the sealing key is lost?

With strict scope the name and the namespace of the SealedSecret are part of what is encrypted. The controller will only decrypt the data into a Secret with exactly that name in exactly that namespace. This stops someone from taking a SealedSecret from Git and using it somewhere they control. For example, a person who can create objects in dso202-dev but cannot read Secrets in dso202-staging cannot copy the staging file into dev, or rename it, to make the controller write the staging password into a Secret they can read. It also means I could not lazily reuse the dev file for staging; each environment had to be sealed on its own.

If the sealing key is lost, every SealedSecret in Git that was sealed with it is useless, permanently. The ciphertext can only be opened with that private key and there is no way to get it back. The Secrets that are already in a running cluster still work while that cluster lives, but on any new cluster (like the rebuild in Task 9) the controller makes a new key, the platform Applications go Degraded with `no key could decrypt secret`, and the Task Tracker Pods cannot start because `tasktracker-credentials` does not exist.

What must be done then:

1. Get the plaintext values back, from the password manager, or from the live Secrets if the old cluster is still running.
2. Let the new controller start with its new key.
3. Seal both environments again with `kubeseal` against the new public key and commit the new files.
4. Take a backup of the new key straight away.

If the plaintext values are also lost, new passwords have to be chosen. In that case the database itself must also be changed, because the postgres image only uses `POSTGRES_PASSWORD` the first time it starts on an empty volume. So either the password is changed inside postgres or the data volume is recreated and the data is lost.

### Q3. What is the difference between Synced and Healthy?

**Synced** is about Git. It means that the objects in the cluster are the same as what the chart and values in Git render to. **Healthy** is about whether those objects actually work: a Deployment has finished its rollout and its Pods are Ready, a StatefulSet has its replica Ready, a Job completed, and so on. The two are independent. Argo CD can apply exactly what Git says (Synced) while what Git says does not work (not Healthy).

**Example from Task 5 (the root Application before the first staging sync).** After bootstrap, `root` had created every child Application, and all of them matched Git, so root was Synced. But `tasktracker-staging` has no automated sync and had never been synced, so its health was Missing. Through the health check in `argocd-cm-patch.yaml` that health is passed up to the root, so the root was Synced but not Healthy. After `argocd app sync tasktracker-staging` the root became Healthy without any change in Git.

> TODO: paste the two `kubectl get applications -n argocd` lines for root (before and after the staging sync) from evidence Task 5 here.

**Example from Task 7.** After the bad backend 1.1 commit, `tasktracker-dev` was Synced (the Deployment in the cluster had image 1.1, exactly as in Git) but Degraded, because the new Pod never became Ready and the Deployment passed its 120 second progress deadline.

### Q4. What does Argo CD RBAC control and what does Kubernetes RBAC control, and where is each one configured? What would change with SSO?

**Argo CD RBAC** controls what a user of Argo CD can do through the Argo CD API server, that is the UI, the `argocd` CLI and the API. The resources are Argo CD things: applications, projects, logs, exec, repositories, clusters, accounts. The actions are get, sync, update, delete, override and so on. It is configured in the `argocd-rbac-cm` ConfigMap (`policy.csv` and `policy.default`), the local accounts are declared in `argocd-cm` (`accounts.reviewer: login`), and projects can have their own roles. When `reviewer` syncs or reads something, the request is carried out by Argo CD's own service accounts, not by the reviewer. The reviewer has no Kubernetes credentials at all.

**Kubernetes RBAC** controls what an identity can do directly against the kube-apiserver: which verbs on which resources in which namespaces. The identities are users with certificates (like `pema` in A2), groups and ServiceAccounts (like `readonly-sa`). It is configured with Role, ClusterRole, RoleBinding and ClusterRoleBinding objects. In this repository that is `platform/<env>/rbac.yaml`, and the ClusterRoles of Argo CD itself from the install manifest.

The two do not know about each other. `readonly-sa` cannot open the Argo CD UI, and `reviewer` cannot run `kubectl`. They also protect each other: anyone with Kubernetes rights to edit ConfigMaps in the argocd namespace could rewrite `argocd-rbac-cm`, so Kubernetes RBAC has to keep the argocd namespace closed for Argo CD RBAC to mean anything.

**With SSO** (Dex or OIDC connected to the organisation's identity provider), users would no longer be local accounts. `accounts.reviewer` and its password would be removed from `argocd-cm`. In `policy.csv` the policies would be given to a role instead of a username, and the identity provider's groups would be mapped to that role with `g` lines, for example:

```text
p, role:dso202-reviewer, applications, get, dso202/*, allow
p, role:dso202-reviewer, projects, get, dso202, allow
p, role:dso202-reviewer, logs, get, dso202/*, allow
g, dso202-reviewers, role:dso202-reviewer
```

where `dso202-reviewers` is the group name sent by the identity provider. `scopes` in `argocd-rbac-cm` would say which claim holds the groups (normally `[groups]`). Adding or removing a reviewer would then happen in the identity provider, not in Git. The local `admin` account would usually be disabled as well.

### Q5. Why is argocd app rollback refused here, what is the GitOps equivalent, and why is git revert better than deleting the bad commit?

`argocd app rollback` deploys an older revision from the Application's history, but it does not change Git. `tasktracker-dev` has automated sync, which keeps making the cluster equal to the tip of `main`. If the rollback were allowed, the cluster would go back to the old backend, Argo CD would then see that it differs from `main` (which still has the bad tag) and sync the bad version again straight away. The two would fight, so Argo CD refuses rollback while automated sync is on.

> TODO: paste the exact refusal message from evidence Task 7, step 7 here.

The GitOps equivalent is to change the desired state in Git: `git revert <bad commit>` on a branch, a pull request, and a merge. Argo CD notices the new commit on `main` and syncs dev back to the old backend tag by itself. The rollback is then a commit like any other release, it is reviewed, and it is in the history.

`git revert` is better than deleting the bad commit (`git reset` and a force push) because:

- The history of `main` stays true. It shows that backend 1.1 was released, broke dev, and was reverted. `argocd app history tasktracker-dev` lists the SHA of the bad commit; if that commit were deleted from history, the deployment record would point to a commit that no longer exists.
- A force push rewrites a shared branch. Everyone else's clone and any open branch based on the old `main` would break, and normally branch protection does not allow it anyway.
- A revert is itself a normal change, so it can be reviewed, and it can be undone later. That is basically what the fix-forward did: it brought backend 1.1 back with the missing setting.

This is GitOps principle 2: the desired state is versioned and immutable, and recovery is a new version, not a rewrite of an old one.

### Q6. (a) Two advantages and two disadvantages of one repository for this project

Advantages:

1. **A change and its configuration move together.** A change to the chart and the values that use it (for example the new `backend.env` map and the variable the fixed backend needed) is one commit and one pull request. One tag such as `v1.2.0` pins the chart and the staging values at the same time, so staging can never get a chart that does not match its values.
2. **Simple for one person.** There is one URL to write identically everywhere, one `sourceRepos` entry per project, one place to clone for the rebuild in Task 9, and one history to read when something breaks.

Disadvantages:

1. **Chart and configuration cannot be versioned separately.** Staging reads everything at the tag, so I cannot promote only a values change without also taking whatever happened to the chart on `main` at that point, and the other way round. This is exactly what Task 10 (multiple sources) is for.
2. **Permissions are all or nothing.** Anyone who can push to the chart can also push to `argocd/` and `platform/`, which means they can create Applications or change quotas. In separate repositories the platform and Argo CD configuration could be limited to a smaller group. The history also mixes chart edits, release bumps, drills and documentation in one log.

### Q6. (b) What is not under GitOps control after the rebuild, and how is it usually handled?

| Not under GitOps | How a production team usually handles it |
|---|---|
| The bootstrap layer (Argo CD install and its ConfigMaps). In Task 6 the RBAC change was committed but only took effect after I re-applied it by hand. | Argo CD is made to manage itself with an Application that points at `bootstrap/argocd`, so after the first install its own upgrades and settings also come from Git. |
| The `platform` project and the `root` Application | They are created by the tool that creates the cluster (for example Terraform or a provisioning pipeline), so a new cluster comes up already pointing at the repository. |
| The sealing key | It is stored in a proper secret store (a vault or a cloud secret manager) with restricted access, backed up after every key renewal, or Sealed Secrets is replaced with an operator that reads secrets from that store. |
| The database contents | Scheduled database backups (for example `pg_dump` or volume snapshots) that are restored and tested regularly, or a managed database service. |
| The kind cluster itself, the initial admin password and the reviewer password | The cluster is created from code; people sign in through SSO and the local admin account is disabled. |

## 10. Problems I ran into

> TODO: write this section from your own run, in your own words. A few lines per problem: what happened, what the error said, how you found the cause, what you changed. Some things that commonly come up in this assignment, if they happen to you:
> - `kubectl apply -k` without `--server-side` failing on the ApplicationSet CRD annotation size
> - a valueFiles comparison error, or the root showing a ComparisonError before `main` was pushed
> - the smoke test or a Pod being rejected by the ResourceQuota
> - Docker Hub rate limits and loading images with `kind load docker-image`
> - `argocd login` as reviewer replacing the admin context
> - what the backend 1.1 log actually asked for, and how long it took to notice
>
> Delete any that did not happen. Only write what really happened.

## 11. References

- Argo CD v3.5.6 documentation: https://github.com/argoproj/argo-cd/tree/v3.5.6/docs (Declarative Setup, Projects, Sync Phases and Waves, Automated Sync Policy, Sync Options, Resource Health, RBAC Configuration, User Management, Multiple Sources, Best Practices)
- Sealed Secrets README (scopes, key renewal, backup and restore): https://github.com/bitnami/sealed-secrets
- OpenGitOps principles: https://opengitops.dev/
- Kubernetes documentation: https://kubernetes.io/docs/ (Deployments and progressDeadlineSeconds, Jobs, StatefulSets, ResourceQuota, RBAC)
- Helm documentation: https://helm.sh/docs/
- Vinto, N., & Bueno, A. (2023). *GitOps Cookbook: Kubernetes Automation in Practice*. O'Reilly Media.
- Andrew, B., & Christian, H. (2025). *Argo CD: Up and Running*. O'Reilly Media.
