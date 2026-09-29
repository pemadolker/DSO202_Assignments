## DSO202 Assignment 2: Applying Unit II to the Task Tracker

**Student:** Pema Dolker    
**Student ID:** 02230294    
**Module:** DSO202: Scaling, Orchestration, Monitoring & Observability

## Table of Contents
 
 1. Introduction   
 2. Environment and Architectural Changes  
 3. StatefulSets (2.1)   
 4. Ingress and Ingress Controllers (2.2)  
 5. Kubernetes RBAC (2.3)  
 6. Kubernetes Operators (2.4)   
 7. Implementation Notes   
 8. Limitations  


## 1. Introduction

No formal brief was issued for this assignment. The only instruction given was: "utilise the concepts and knowledge gained from the Unit 2 lectures to effectively implement Assignment 1." In the absence of a rubric, the Unit II module descriptor topic list was used as the specification for this report, down to its numbered sub-points (2.1–2.4). Each sub-point is addressed either through a change made to the running cluster, with evidence, or through a written explanation stating why it is addressed in writing rather than built.

This assignment extends the Assignment 1 application rather than replacing it: the same Task Tracker, the same three-tier architecture, and the same namespace (`dso202-assignment-01`). Configuration already established in A1 (the ConfigMap/Secret split, the image architecture issue, and the original CRUD verification) is not repeated here; it remains part of the A1 submission and continues to apply unchanged.

## 2. Environment and Architectural Changes

The working directory `assignment-2/` was created by copying `assignment-1/`, so that the A1 submission remains untouched. The kind cluster was also rebuilt, since kind's port mappings are fixed at cluster creation and an Ingress controller requires host ports 80 and 443 to be mapped in, with the node labelled `ingress-ready=true`. The previous NodePort mapping (30080) was retained for comparison, although the frontend no longer uses it once Ingress is in place.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 30080
        hostPort: 30080
        protocol: TCP
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
```

Recreating the cluster has no effect on the A1 submission, which was committed and pushed separately.

The application images remain the amd64 rebuilds used in A1 (`pdolker/dso202-{frontend,backend,db}:1.0`), since the tutor-issued `sarojsanyasi/...` images are published for arm64 only. Every `image:` line still carries the `# TEMP` comment from A1, marking it for replacement if amd64 images are published later.

## 3. StatefulSets (2.1)

### 3.1 Use cases for StatefulSets (2.1.1)

Assignment 1 used a Deployment with a manually-created PVC for the database, which is appropriate at a single replica. A StatefulSet becomes necessary once replicas are not interchangeable: when each one requires a stable identity, a stable network address, and storage that follows it across rescheduling. A Deployment provides none of this: any replica can be removed and replaced by an identical one under a new, randomly-suffixed name. That model is correct for a stateless API, but not for a workload where individual replica identity matters, such as a coordinated database cluster.

### 3.2 Deploying stateful applications (2.1.2)

The `db` workload was converted from a Deployment to a StatefulSet. This required deleting the existing Deployment and its manually-created `db-pvc`, then applying the StatefulSet, which provisions its own PVC through a template. The seed data was lost in the process, which is not significant here: the postgres image reseeds the sample tasks automatically the first time it starts against an empty volume.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
  namespace: dso202-assignment-01
spec:
  serviceName: db-svc
  replicas: 1
  podManagementPolicy: OrderedReady
  selector:
    matchLabels: { app: task-tracker, tier: database }
  template:
    metadata:
      labels: { app: task-tracker, tier: database }
    spec:
      containers:
        - name: postgres
          image: pdolker/dso202-db:1.0
          env:
            - { name: POSTGRES_DB, valueFrom: { configMapKeyRef: { name: app-config, key: POSTGRES_DB } } }
            - { name: POSTGRES_USER, valueFrom: { secretKeyRef: { name: db-credentials, key: POSTGRES_USER } } }
            - { name: POSTGRES_PASSWORD, valueFrom: { secretKeyRef: { name: db-credentials, key: POSTGRES_PASSWORD } } }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 256Mi }
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql/data }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard
        resources: { requests: { storage: 1Gi } }
  updateStrategy: { type: RollingUpdate }
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Delete
```

Replica count was kept at 1 for the running application. The `postgres` image has no built-in replication logic; it has no concept of a primary or a follower, and does not synchronise data with any other instance. Running it at three replicas permanently would not produce a database cluster; it would produce three unrelated databases that happen to share a naming pattern. This is demonstrated directly, not assumed, in Section 3.3.

`whenDeleted: Retain` and `whenScaled: Delete` were set deliberately rather than left at default. Scaling a replica down (as done for the demonstration in 3.3) is expected to discard that replica's data, since it only ever holds a disposable copy; deleting the StatefulSet itself should not.

![Database converted to StatefulSet, seed data reloaded, stable DNS confirmed](evidence/01-statefulset-db.png)

#### 3.2.1 Stable network identities (2.1.2.1)

```bash
kubectl exec db-0 -- psql -U taskuser -d taskdb -c "SELECT id, title FROM tasks;"
kubectl run -it --rm dnscheck --image=busybox:1.36 --restart=Never -- \
  nslookup db-0.db-svc.dso202-assignment-01.svc.cluster.local
```

`db-0` is a fixed, predictable Pod name; the equivalent Deployment Pod in A1 was named `db-564c5c7db4-rcqh5`, with a random suffix. `nslookup` resolved `db-0.db-svc...` directly to the Pod's own IP address (`10.244.0.11`). The Service was already headless in A1 and required no change; the StatefulSet's use of it is what produces a stable, individual DNS name for each replica.

#### 3.2.2 Ordered deployment and scaling (2.1.2.2)

```bash
kubectl scale statefulset db --replicas=3
kubectl get pods -l tier=database --watch
```

`db-1` did not start until `db-0` was `Running` and `1/1`; `db-2` did not start until `db-1` was ready. Pod creation proceeded strictly in order. Scaling back down reversed this: `db-2` terminated first, then `db-1`, leaving only `db-0`.

To confirm that the three replicas are independent databases rather than a coordinated cluster:

```bash
kubectl exec db-0 -- psql -U taskuser -d taskdb -c "INSERT INTO tasks (title, status) VALUES ('only in db-0', 'pending');"
kubectl exec db-1 -- psql -U taskuser -d taskdb -c "SELECT id, title FROM tasks;"
kubectl exec db-2 -- psql -U taskuser -d taskdb -c "SELECT id, title FROM tasks;"
```

The row inserted into `db-0` was absent from both `db-1` and `db-2`, confirming the point made in Section 3.2: no synchronisation takes place between replicas, because the image contains no logic to perform it.

![Ordered scale-up to 3 replicas, PVCs created per replica](evidence/02b-statefulset-scaling-fixed.png)
![Independent data proof: the row inserted into db-0 does not exist in db-1 or db-2](evidence/02c-statefulset-independent-data.png)
![Ordered scale-down back to 1, extra PVCs auto-deleted](evidence/03-statefulset-scaledown.png)

### 3.3 Headless Services for StatefulSets (2.1.3)

`db-svc` was already configured as headless (`clusterIP: None`) in A1, and required no modification. Its original purpose (a stable in-namespace name for the database, with no external exposure) already matched what a StatefulSet requires. The only change needed was referencing it in the StatefulSet's `serviceName` field, which is what establishes the relationship and produces the per-Pod DNS names described in Section 3.2.1. Without this field pointing at a genuinely headless Service, no per-Pod DNS behaviour occurs.

### 3.4 Volume claim templates (2.1.4)

In place of a single, manually-created PVC, `volumeClaimTemplates` generates one PVC per replica, named `data-<pod-name>`. Scaling to three replicas produced `data-db-0`, `data-db-1`, and `data-db-2`, each 1Gi, bound independently. On rescheduling, a Pod reattaches to its own identically-named PVC rather than receiving a new one; this was not tested directly against a forced reschedule within this assignment, but follows from the naming being tied to ordinal position, and is consistent with the Pod/PVC lifecycle independence already demonstrated in A1's single-replica self-healing test.

Scaling to three replicas exceeded the ResourceQuota configured in A1, in two separate respects:

```text
persistentvolumeclaims "data-db-2" is forbidden: exceeded quota: ns-quota,
requested: persistentvolumeclaims=1, used: persistentvolumeclaims=2, limited: persistentvolumeclaims=2
```

`persistentvolumeclaims` was raised to 4, but `db-2` did not appear after this change alone. This is consistent with the StatefulSet controller only re-evaluating Pod and PVC creation in response to a change in the StatefulSet's own desired state, rather than watching the ResourceQuota object directly. A scale-down followed by a scale-up forced a fresh reconciliation attempt, which then exposed a second limit:

```text
pods "db-2" is forbidden: exceeded quota: ns-quota,
requested: limits.memory=256Mi, used: limits.memory=832Mi, limited: limits.memory=1Gi
```

The actual peak required was calculated rather than estimated: `db` at three replicas, plus `backend` and `frontend`, gives a peak of 1850m CPU / 1088Mi memory during a scaling operation. `limits.memory` was set to 1200Mi, sized directly against that figure rather than rounded arbitrarily, and `persistentvolumeclaims` to 4 (three replicas plus one spare). `limits.cpu` was left unchanged, since A1's value of 2 already covers the 1850m peak.

![Final quota, sized for the scaling demonstration's peak usage](evidence/03-statefulset-scaledown.png)

## 4. Ingress and Ingress Controllers (2.2)

### 4.1 Ingress resource configuration (2.2.1)

A1 exposed the frontend using a NodePort Service. In A2, a single Ingress resource handles both routing and TLS termination, which is the purpose Ingress serves: one entry point rather than one NodePort per application.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: task-tracker-ingress
  namespace: dso202-assignment-01
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "5"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [tasktracker.local, api.tasktracker.local]
      secretName: tasktracker-tls
  rules:
    - host: tasktracker.local
      http:
        paths:
          - { path: /api, pathType: Prefix, backend: { service: { name: backend-svc, port: { number: 8080 } } } }
          - { path: /,    pathType: Prefix, backend: { service: { name: frontend-svc, port: { number: 8080 } } } }
    - host: api.tasktracker.local
      http:
        paths:
          - { path: /, pathType: Prefix, backend: { service: { name: backend-svc, port: { number: 8080 } } } }
```

`ingressClassName` was used to select the controller, in preference to the deprecated `kubernetes.io/ingress.class` annotation; `pathType: Prefix` was used on every rule to keep path matching explicit and portable, rather than relying on controller-specific implicit matching.

The worked example in the lecture notes uses a `rewrite-target: /` annotation, which was deliberately not applied here. That annotation rewrites the matched path to `/` before forwarding, which is appropriate for a backend expecting bare paths, but not for this backend, whose routes are `/api/tasks`, `/api/status`, and so on. Applying the example unmodified would have rewritten every API call to `/`, breaking the API entirely; the assumption behind the example was checked against the backend before use.

With Ingress providing external access, `frontend-svc` no longer requires a NodePort. It was changed from `type: NodePort` to `type: ClusterIP` accordingly.

![alt text](evidence/04-ingress-controller.png)

![Ingress created with both hosts listed, frontend-svc now ClusterIP](evidence/05-ingress-created.png)

#### 4.1.1 Basic routing rules (2.2.1.1)

```bash
curl -sk https://tasktracker.local/api/status
curl -sk https://tasktracker.local/ | head -3
```

`/api/status` returned the backend's JSON response; `/` returned the frontend's HTML. Both requests used the same host and port, routed to different Services purely by path.

#### 4.1.2 TLS termination (2.2.1.2)

No real domain is available for a kind cluster, so a self-signed certificate was generated for both hostnames and stored in a Secret of type `kubernetes.io/tls`:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tasktracker.key -out tasktracker.crt \
  -subj "/CN=tasktracker.local/O=dso202" \
  -addext "subjectAltName=DNS:tasktracker.local,DNS:api.tasktracker.local"
kubectl create secret tls tasktracker-tls --cert=tasktracker.crt --key=tasktracker.key -n dso202-assignment-01
```

Both `curl` requests above used `https://` with the `-k` flag, which accepts a certificate that cannot be verified against a trusted authority; without it, curl connects but then refuses to proceed once certificate verification fails, which is the correct behaviour for a self-signed certificate. TLS is terminated at the Ingress controller: the frontend and backend Pods behind it receive plain HTTP, with no TLS handling of their own.

![Path routing and TLS termination both working](evidence/06-ingress-routing-tls.png)

#### 4.1.3 Name-based virtual hosting (2.2.1.3)

`tasktracker.local` and `api.tasktracker.local` were both mapped to `127.0.0.1` in `/etc/hosts`, so they resolve to the same address, but Ingress routes them differently: the first serves the full application, the second routes every path directly to the backend only. This was confirmed with identical requests against both hosts:

```bash
curl -sk https://tasktracker.local/api/status
curl -sk https://api.tasktracker.local/api/status
```

Both returned the same backend JSON, which is the expected result: `api.tasktracker.local` forwards `/*` to the backend directly, so `/api/status` reaches the same endpoint through a different rule. The distinction between the two hosts is clearer at `/`: `tasktracker.local` returns the frontend's HTML, while `api.tasktracker.local` returns the backend's own 404 response for that path, since the backend has no route defined at `/`.

![Two hostnames on the same IP and port, routed by separate Ingress rules](evidence/07-ingress-virtualhost.png)

### 4.2 Setting up Ingress Controllers (2.2.2)

#### 4.2.1 NGINX Ingress Controller (2.2.2.1)

The controller was installed using kind's dedicated deployment manifest, built specifically for kind's `hostPort`-based exposure rather than requiring a cloud LoadBalancer:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
```

The initial `kubectl wait` timed out after 180 seconds. `kubectl describe pod` showed two separate, non-fatal causes in sequence: a `FailedMount: secret "ingress-nginx-admission" not found` event for the first few minutes, caused by the controller Pod being scheduled slightly before the admission webhook's certificate-setup Job completed, which resolved on its own; and a controller image pull that took 2 minutes 54 seconds, exceeding the wait timeout. The container started successfully once the pull completed.

![Controller confirmed Running and 1/1, IngressClass nginx registered](evidence/04-ingress-controller.png)

#### 4.2.2 Traefik Ingress Controller (2.2.2.2)

Traefik was not installed alongside NGINX. Running two Ingress controllers in a single small cluster, for one small application, is not representative of how a production team would operate, so this section is addressed in writing rather than through a second installation.

Traefik and the NGINX Ingress Controller address the same problem (Layer 7 routing of external HTTP(S) traffic into the cluster) but differ in implementation. Traefik is written in Go and provides native custom resources (`IngressRoute` and related CRDs) in addition to standard `Ingress` support, allowing routing configurations that the base `Ingress` specification cannot express without controller-specific annotations. It also includes a built-in dashboard for inspecting live routing state, and native integration with Let's Encrypt for certificate issuance. Controller-specific behaviour is configured through annotations in both controllers, using different prefixes (`traefik.ingress.kubernetes.io/...` versus `nginx.ingress.kubernetes.io/...`), which is the concrete instance of the general point made in the lecture notes: annotations are controller-specific and are never portable between controllers.

The choice between the two carries more weight currently than it would have previously. The lecture notes state that the NGINX Ingress Controller, used here and historically the most widely deployed option, entered maintenance mode as of 2026, with no further releases, bug fixes, or security updates from March 2026 onward. It was used in this assignment because the lecture notes' own worked example is built around it and it is the most thoroughly documented option for kind specifically; a team making this decision for a new production system today would need to weigh that maintenance status against Traefik or the newer Kubernetes Gateway API as longer-term alternatives.

### 4.3 Ingress annotations for controller-specific features (2.2.3)

The `nginx.ingress.kubernetes.io/limit-rps: "5"` annotation was applied, limiting each client IP to 5 requests per second. To confirm the annotation was genuinely enforced rather than merely present in the manifest, load was applied directly:

```bash
for i in $(seq 1 40); do curl -sk -o /dev/null -w "%{http_code}\n" https://tasktracker.local/api/status; done | sort | uniq -c
```

28 requests returned `200`; 12 returned `503`. An earlier attempt at 10 requests had not been sufficient to trigger the limit, since `limit_req` permits some burst above the configured rate. The rendered NGINX configuration was also checked directly to confirm the annotation had produced an active `limit_req_zone`.

![28 requests succeeded, 12 were rejected once load exceeded the configured rate](evidence/08-ingress-ratelimit.png)

## 5. Kubernetes RBAC (2.3)

A1's optional Task 8 established a single Role bound to a single ServiceAccount, granting read-only namespace access. This section extends that to cover Role versus ClusterRole, aggregation specifically, and binding to all three subject types named in the descriptor: users, groups, and service accounts.

### 5.1 Roles and ClusterRoles (2.3.1)

#### 5.1.1 Defining permissions for resources (2.3.1.1)

The backend was given a dedicated ServiceAccount and Role, replacing the namespace's default ServiceAccount it previously ran under. The lecture notes identify use of the default ServiceAccount as something to avoid, since permissions granted to it are implicitly shared by every Pod in the namespace that does not request a different one.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backend-role
  namespace: dso202-assignment-01
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
```

The backend application does not currently call the Kubernetes API for any functional purpose; it is a REST server communicating with PostgreSQL. This Role and ServiceAccount exist to demonstrate the mechanism, not to serve an existing application need. Read-only access to Pods was chosen specifically to provide a controlled contrast against Secrets in Section 5.3.2.

#### 5.1.2 Aggregated ClusterRoles (2.3.1.2)

Kubernetes' built-in `edit`, `view`, and `admin` ClusterRoles are not static rule sets; each carries a label selector, and the API server automatically merges in the rules of any ClusterRole matching that selector. To demonstrate this concretely rather than describe it abstractly, a resource genuinely not covered by `edit` was required. Since `edit` already covers nearly all built-in resource types, this required a Custom Resource Definition: `TaskTrackerBackup`, also used in Section 6, which is guaranteed to start with zero permissions granted anywhere.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tasktrackerbackup-editor
  labels:
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
rules:
  - apiGroups: ["dso202.example.com"]
    resources: ["tasktrackerbackups"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

Before this ClusterRole was applied, a check of whether `pema` (bound to `edit` via a namespace-scoped RoleBinding) could create a `tasktrackerbackup` returned `no`. After applying the ClusterRole above, with no direct modification to `edit`, the same check returned `yes`. The mechanism itself was also inspected directly:

```bash
kubectl get clusterrole edit -o jsonpath='{.aggregationRule}'
kubectl get clusterrole edit -o jsonpath='{.rules[?(@.apiGroups[0]=="dso202.example.com")]}'
```

The first command returned `edit`'s label selector, matching the label on the new ClusterRole; the second returned the `tasktrackerbackups` rule already merged into `edit`'s own rule list, confirming the aggregation occurred without any direct edit to the built-in role.

![Before: edit does not cover the new CRD](evidence/18-edit-before-aggregation.png)
![After: edit covers it immediately; aggregationRule and merged rules shown](evidence/19-edit-after-aggregation.png)

### 5.2 RoleBindings and ClusterRoleBindings (2.3.2)

#### 5.2.1 Binding roles to users, groups, and service accounts (2.3.2.1)

Kubernetes has no `User` object. A user identity is established by issuing a certificate the API server trusts, then binding a Role to the identity encoded within it. A certificate was generated for this purpose:

```bash
openssl genrsa -out pema.key 2048
openssl req -new -key pema.key -out pema.csr -subj "/CN=pema/O=dso202-students"
```

The request was signed through the cluster's own CertificateSigningRequest API, using the signer the API server accepts for client authentication:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: pema
spec:
  request: ${REQ}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 7776000
  usages: [client auth]
EOF
kubectl certificate approve pema
```

`CN=pema` became the username, bound directly to a Role:

```bash
kubectl create rolebinding pema-reader --namespace=dso202-assignment-01 --role=namespace-reader --user=pema
```

Access was verified by switching to the identity through a genuine kubeconfig context, not through `--as=` impersonation, and testing scope in both directions:

```bash
kubectl config use-context pema-context
kubectl get pods                    # succeeds
kubectl get secrets                 # Forbidden: not granted by the Role
kubectl get pods -n kube-system     # Forbidden: RoleBinding is namespace-scoped
kubectl get nodes                   # Forbidden: cluster-scoped, a Role cannot grant this
```

The API server's response to the last check was specific rather than generic: `Forbidden ... at the cluster scope`, correctly distinguishing a scope mismatch from a missing rule.

![Access within the user's own namespace; correctly refused everywhere else](evidence/15-user-context-scoped.png)

A second identity, `CN=classmate-demo`, was issued in the same `O=dso202-students` group and given no personal binding. Access was granted purely through a group-scoped RoleBinding:

```bash
kubectl create rolebinding dso202-students-reader --namespace=dso202-assignment-01 --role=namespace-reader --group=dso202-students
```

Switching to the `classmate-demo` context and running `kubectl get pods` succeeded, despite this identity being named in no RoleBinding, only in the group it belongs to.

![namespace-reader bound to a user and to a group, both functioning](evidence/16-group-role.png)
![classmate-demo reading Pods through group membership alone](evidence/17-group-context-works.png)

The bindings above are both RoleBindings, which are namespace-scoped by definition. To address the ClusterRoleBinding half of this descriptor section explicitly, the `dso202-students` group was bound to the built-in `view` ClusterRole cluster-wide:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dso202-students-viewer-clusterwide
subjects:
  - { kind: Group, name: dso202-students, apiGroup: rbac.authorization.k8s.io }
roleRef:
  { kind: ClusterRole, name: view, apiGroup: rbac.authorization.k8s.io }
```

The verification initially failed, for a reason worth recording precisely: `kubectl get pods -n kube-system --as=classmate-demo` impersonates only the username, not group membership. Group membership exists only within the certificate itself and is applied automatically when switching to a real kubeconfig context; plain `--as=` impersonation does not read it. The correct check requires `--as-group=` explicitly:

```bash
kubectl get pods -n kube-system --as=classmate-demo --as-group=dso202-students
```

With the group included, the same identity that was `Forbidden` a moment earlier could list every control-plane Pod in `kube-system`. A check against the `default` namespace returned "No resources found," which is distinct from `Forbidden`: the permission check succeeded, and the namespace was simply empty. This is the direct, functional difference between the two binding types: identical subject, refused outside its own namespace under a RoleBinding, permitted cluster-wide under a ClusterRoleBinding.

![Before: Forbidden outside the namespace. After: cluster-wide access via the ClusterRoleBinding](evidence/22-clusterrolebinding.png)

### 5.3 Service Accounts (2.3.3)

#### 5.3.1 Creating and managing service accounts (2.3.3.1)

`backend-sa` was created as shown in Section 5.1.1. Attaching it to the backend Deployment required one addition:

```yaml
spec:
  template:
    spec:
      serviceAccountName: backend-sa
```

A Pod's ServiceAccount is fixed at creation time, so the change did not take effect until the Deployment was restarted:

```bash
kubectl rollout restart deployment/backend
kubectl get pod -l tier=backend -o jsonpath='{.items[0].spec.serviceAccountName}'
```

This confirmed `backend-sa`, replacing the default ServiceAccount.

![Backend Pod running under its dedicated ServiceAccount](evidence/09-backend-sa.png)

#### 5.3.2 Using service accounts for pod authentication (2.3.3.2)

Permissions can be checked hypothetically from outside the cluster:

```bash
kubectl auth can-i list pods --as=system:serviceaccount:dso202-assignment-01:backend-sa -n dso202-assignment-01   # yes
kubectl auth can-i get secrets --as=system:serviceaccount:dso202-assignment-01:backend-sa -n dso202-assignment-01 # no
```

![can-i checks for backend-sa: permitted on Pods, refused on Secrets](evidence/10-sa-can-i.png)

To verify the same result from a genuine request rather than a hypothetical check, a short-lived Pod was launched under `backend-sa`, and made to authenticate to the API server directly using its own mounted token:

```bash
kubectl run debug-as-backend --rm -i --image=curlimages/curl --restart=Never \
  --overrides='{"spec": {"serviceAccountName": "backend-sa"}}' \
  -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/dso202-assignment-01/pods
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/dso202-assignment-01/secrets
'
```

The result was `HTTP 200` on Pods and `HTTP 403` on Secrets: the same RBAC decision, this time produced by an actual authenticated request from inside a running Pod, using its own credential, rather than an external simulation of one. This also illustrates two distinct access paths for the same category of data: the backend receives its database password as an environment variable, injected from a Secret at container start, but its own API identity is refused any direct read access to Secrets whatsoever. This is the practical distinction the Create_CSR guide makes between authentication and authorisation: a valid credential establishes who is asking, but grants nothing on its own; RBAC decides separately what that identity may do.

![Authenticated API request from inside a Pod, using its own mounted ServiceAccount token](evidence/11-sa-pod-auth.png)

## 6. Kubernetes Operators (2.4)

### 6.1 Operator pattern (2.4.1)

The Operator pattern packages application-specific operational knowledge (failover, backup, upgrade procedures for a particular piece of software) into a controller that watches a Custom Resource and reconciles the cluster's actual state to match it. This is the same reconcile-loop architecture used by every built-in Kubernetes controller, applied to logic specific to one application rather than to Kubernetes itself. An Operator is also, itself, a workload subject to RBAC (Section 5); the permissions granted to its ServiceAccount require the same scrutiny applied in Section 5.1.1, since an Operator typically needs broader create/update/delete permissions than a stateless application does.

#### 6.1.1 Custom Resources and Custom Resource Definitions (2.4.1.1)

A CRD was defined representing a possible future object for scheduling database backups of the Task Tracker:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: tasktrackerbackups.dso202.example.com
spec:
  group: dso202.example.com
  names: { kind: TaskTrackerBackup, plural: tasktrackerbackups, singular: tasktrackerbackup }
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      subresources: { status: {} }
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties: { schedule: { type: string }, retentionDays: { type: integer } }
            status:
              type: object
              properties: { phase: { type: string } }
```

with an instance created against it:

```yaml
apiVersion: dso202.example.com/v1
kind: TaskTrackerBackup
metadata:
  name: nightly-backup
  namespace: dso202-assignment-01
spec:
  schedule: "0 2 * * *"
  retentionDays: 7
```

The purpose of this section is to demonstrate that a CRD alone provides no functionality. `kubectl apply` and `kubectl get` operate on it exactly as they would on a built-in resource type, since a StorageClass with `volumeBindingMode: WaitForFirstConsumer` (the same mode used by kind's default StorageClass, which is why the PVCs above show `waiting for first consumer to be created before binding` until a Pod is scheduled) is a comparable example of Kubernetes deferring an action until the right conditions exist. A CRD defers indefinitely, because nothing exists to act on it at all:

```bash
kubectl describe tasktrackerbackup nightly-backup   # Status: (empty); Events: <none>
kubectl get pods,jobs,cronjobs                      # no backup-related resources present
```

Despite the spec stating a schedule explicitly, nothing executes at the stated time, because no controller in the cluster watches `TaskTrackerBackup` objects. The status field remained empty after an extended period, confirming this is a structural absence of a controller rather than a delay.

![CRD stored and readable like a built-in object, with no controller acting on it](evidence/21-crd-no-controller.png)

#### 6.1.2 Operator lifecycle management (2.4.1.2)

A running Operator still requires installation, upgrading, and permission management like any other workload. In some ecosystems, particularly Red Hat OpenShift, this is handled by a dedicated tool, the Operator Lifecycle Manager (OLM). OLM was not installed for this assignment; it is a separate system for managing Operators themselves, and the lecture notes identify it only as something to be aware of, not as material requiring hands-on treatment in this unit. The stage OLM is designed to manage is demonstrated directly here: the `TaskTrackerBackup` CRD, installed with no controller watching it, is precisely the starting state every real Operator installation begins from, before a controller Deployment is ever applied.

### 6.2 Creating custom operators (2.4.2)

#### 6.2.1 Operator SDK (2.4.2.1)

Operator SDK and Kubebuilder generate the CRD scaffolding, the watch/informer/workqueue plumbing, and the RBAC manifests an Operator requires, so that an author writes reconciliation logic without reimplementing this machinery directly. Neither was used here, since building a functioning Operator is explicitly identified in the lecture notes as beyond this unit's scope. The connection to work already completed is direct: the aggregated ClusterRole built in Section 5.1.2 is similar in purpose to the RBAC manifests these tools would generate automatically for a real `TaskTrackerBackup` Operator; it was constructed by hand here specifically to demonstrate how that mechanism functions.

#### 6.2.2 Writing controllers for custom resources (2.4.2.2)

No controller was implemented. The reconciliation logic a `TaskTrackerBackup` controller would require can be described directly, based on the reconcile loop presented in the lecture notes:

```text
function reconcile(taskTrackerBackup):
    desired = taskTrackerBackup.spec                       # schedule, retentionDays
    current = getExistingResourcesFor(taskTrackerBackup)    # any CronJob already created

    if current.cronJob is missing:
        createCronJob(desired.schedule)                     # runs pg_dump against db-svc
    else if current.cronJob.schedule != desired.schedule:
        updateCronJobSchedule(desired.schedule)

    pruneBackupsOlderThan(desired.retentionDays)             # application-specific, not built into K8s
    updateStatusCondition(taskTrackerBackup, observedGeneration=...)
```

The lecture notes require this logic to be level-based: comparing the current desired state against the current actual state, rather than tracking which specific field changed. This matters directly in this environment: the `nightly-backup` object used here sat with an empty status for as long as it was left untouched, and a controller must be able to restart, miss an update entirely, or rebuild its cache from nothing, and still reach the correct state on its next pass. Logic that instead tracks "what changed" fails precisely under those conditions.

### 6.3 Examples of popular operators (2.4.3)

This connects directly to the decision made in Section 3.2 to keep `db` at a single replica: a plain `postgres` container cannot coordinate multiple instances of itself, as demonstrated by the independent-data test in Section 3.2.2. A production PostgreSQL operator (**CloudNativePG** or the **Zalando Postgres Operator** are the two most commonly used) closes this gap. Both manage a StatefulSet internally, the same object type built manually in Section 3, but add the application-specific knowledge a StatefulSet alone does not provide: electing a primary among replicas, configuring streaming replication so replicas remain synchronised, performing automatic failover on primary failure, and taking scheduled backups. This is the functionality the `TaskTrackerBackup` CRD in Section 6.1.1 represents in outline, without any controller behind it. The **Prometheus Operator** is the other commonly cited example, managing Prometheus and Alertmanager deployments through its own CRDs (`Prometheus`, `ServiceMonitor`), covered separately in Unit V.

## 7. Implementation Notes

The following issues arose during implementation and are recorded for completeness, each with its cause and resolution.

| Issue | Cause | Resolution |
|---|---|---|
| Ingress controller `FailedMount` and slow readiness | Admission webhook Job completing after the controller Pod was scheduled; controller image pull exceeding the wait timeout | Confirmed via `kubectl describe pod`; resolved without intervention once the pull completed (Section 4.2.1) |
| StatefulSet scaling blocked by quota (PVC count, then memory limit) | A1's ResourceQuota was sized for a single-replica database | Quota raised and re-justified against the calculated scaling peak; StatefulSet controller does not watch the ResourceQuota directly, so a scale-down/scale-up was needed to trigger re-evaluation (Section 3.4) |
| `kubectl get pods --as=` did not reflect group membership | `--as=` impersonates a username only; group membership is only read from an actual certificate or an explicit `--as-group=` flag | Corrected by adding `--as-group=dso202-students` to the verification command (Section 5.2.1) |

## 8. Limitations

- The database runs as a single StatefulSet replica in the deployed configuration. Three-replica behaviour is demonstrated deliberately (Section 3.2.2) and then reverted, since a genuinely useful multi-replica deployment requires an Operator (Section 6.3) to manage replication, which is outside this assignment's scope.
- TLS uses a self-signed certificate, since no real domain is available for a kind cluster. A production deployment would use cert-manager with a trusted certificate authority, as identified in the lecture notes.
- x509 client certificates, as used for the `pema` and `classmate-demo` identities, cannot be revoked in Kubernetes; access can only be removed by deleting the associated RoleBinding or waiting for the certificate to expire (90 days, in this case). A shared or long-lived cluster would use ServiceAccount tokens or an OIDC provider instead, as noted in the Create_CSR reference material.
- `TaskTrackerBackup` is a CRD with no controller. This is deliberate, demonstrating the CRD/controller distinction described in Section 6.1.1, and matches the lecture notes' own statement that building a working controller is beyond this unit's scope.
- The backend's RBAC permissions (read-only on Pods) are not consumed by the application's own logic; they exist solely to demonstrate the ServiceAccount authentication mechanism described in Section 5.3.2.

