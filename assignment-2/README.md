# DSO202 Assignment 2: Applying Unit II to the Task Tracker
### Student name: Pema Dolker   
### student id : 02230294    
### Module : DSO202  


There wasn't any proper brief for this particular assignment but only one sentence on the portal which stated "make use of the concepts and knowledge acquired in Unit 2 lectures in order to effectively perform Assignment 1." Therefore, rather than speculating the rubric, I utilized the module descriptor topics list as my checklist (2.1 to 2.4, even the numbered sub-points of each topic) and ensured that all of them are either implemented in the cluster or documented with the rationale as to why they are documented instead of being implemented.

This is an enhancement of Assignment 1 app rather than a new one; similar task tracker, similar three-tier architecture, and namespace. I have not included the details of A1's readme file (ConfigMap/Secret configuration, the arm64 image issue, and the original CRUD implementation evidence) as they were submitted separately and remain relevant for this  assignment's readme file too.


## 1. What changed structurally

The folder `assignment-2/` has been created through the process of copying `assignment-1/`, which allows A1 to remain untouched. Also, the kind cluster had to be recreated because the port mapping of the kind clusters can’t be altered once they have been created and Ingress requires host port 80/443 to bemapped in, and the node has to be labelled ingress-ready=true. The old NodePort 30080 has been kept for the sake of comparison with the previous assignment.


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

Recreating the cluster will have no effect on my A1 submission since it is already committed and pushed. 

This is because my images are still my personal amd64 build (pdolker/dso202-{frontend,backend,db}:1.0) just like in A1 submission since the tutor's sarojsanyasi/… images on Docker Hub are arm64-only, as checked on this cluster. Every image tag still has the "# TEMP" comment from A1 submission.

## 2.1 StatefulSets

### 2.1.1 Use cases for StatefulSets

For A1, it was intentional to create a Deployment with a manually created PVC for the database since with just one replica, it’s easy and effective. What makes someone choose to use StatefulSet is that they are not interchangeable and need their own identity, network addresses and usually follow around the same storage as long as they are rescheduled. It is because of that fact that Deployment doesn’t track anything and any of the replicas can be killed and replaced with another replica that will have a different name. It works well with stateless APIs, but not with a database cluster.


### 2.1.2 Deploying stateful applications

I have changed `db` from Deployment to StatefulSet. This required the deletion of Deployment and of the `db-pvc` that I had created manually, followed by the deployment of the StatefulSet. The new StatefulSet creates a Persistent Volume Claim using a template, and this causes the loss of the seed data; however, that is really not an issue in this case because the postgres image automatically seeds the sample tasks in an empty volume the first time it gets launched.

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

I kept `replicas: 1` for the actual application running. A regular `postgres` container does not have any replication capabilities implemented in itself - it knows nothing about being either primary or a follower, syncing data with anything, etc. Having three replicas of this type on a permanent basis would result in having three separate databases sharing the naming pattern, but not a cluster of any kind (see in 2.1.2.2). I think that this is an honest demonstration of the idea rather than an assumption that three replicas somehow make something special.

`whenDeleted: Retain` and `whenScaled: Delete` were intentionally chosen as a pair of parameters, not default values untouched. In case when I will scale my replica down (and I do, for the demonstration of scaling below), the data would get automatically deleted since it was supposed to be a disposable additional instance anyway. However, in case I mistakenly decide to delete a StatefulSet, the actual data remains intact.

![Database converted to StatefulSet, seed data reloaded, stable DNS confirmed](evidence/01-statefulset-db.png)

### 2.1.2.1 Stable network identities

```bash
kubectl exec db-0 -- psql -U taskuser -d taskdb -c "SELECT id, title FROM tasks;"
kubectl run -it --rm dnscheck --image=busybox:1.36 --restart=Never -- \
  nslookup db-0.db-svc.dso202-assignment-01.svc.cluster.local
```


db-0 is a fixed name; the Deployment Pod I had before was db-564c5c7db4-rcqh5, with a random suffix.  The command `nslookup db-0.db-svc...` resulted in getting the Pod's very own IP address `10.244.0.11`, which shows that the headless Service (the Service is already headless in A1, nothing had to be changed about it) assigns an individual DNS name to each StatefulSet Pod.

### 2.1.2.2 Ordered deployment and scaling

```bash
kubectl scale statefulset db --replicas=3
kubectl get pods -l tier=database --watch
```

`db-1` started running after `db-0` was already `Running` and `1/1`, and db-2 started after `db-1` was ready. It means that the pods launched one by one, sequentially, in order. And it worked backwards when I scaled down: `db-2` terminated first, then `db-1`, leaving only `db-0`.

I also proved the three replicas really are independent databases, not a cluster:

```bash
kubectl exec db-0 -- psql -U taskuser -d taskdb -c "INSERT INTO tasks (title, status) VALUES ('only in db-0', 'pending');"
kubectl exec db-1 -- psql -U taskuser -d taskdb -c "SELECT id, title FROM tasks;"
kubectl exec db-2 -- psql -U taskuser -d taskdb -c "SELECT id, title FROM tasks;"
```

In neither database `db-1` nor `db-2` had the row  I just added to `db-0`. This is the concrete example of what I discussed above in 2.1.1, that is, no one is syncing anything because no one in the picture knows how to sync anything.

![Ordered scale-up to 3 replicas, PVCs created per replica](evidence/02b-statefulset-scaling-fixed.png)
![Independent data proof — the row inserted into db-0 doesn't exist in db-1 or db-2](evidence/02c-statefulset-independent-data.png)
![Ordered scale-down back to 1, extra PVCs auto-deleted](evidence/03-statefulset-scaledown.png)

### 2.1.3 Headless Services for StatefulSets


`db-svc` was already `clusterIP: None` from A1 - no need for any changes here, as the logic for this provided by A1 (stable name for the database within the namespace, no outside exposure) already aligned perfectly with the requirements of the StatefulSet. It was sufficient to link the `serviceName` attribute of the StatefulSet to it, which would effectively make this relationship and give rise to the DNS names of 2.1.2.1 through that link. Without that field pointing at a genuinely headless Service, none of that DNS behaviour happens.


### 2.1.4 Volume claim templates


Rather than my one PVC that I create manually, `volumeClaimTemplates` enables Kubernetes to create one PVC per replica for me, named `data-<pod-name>`. Thus scaling to 3 replicas created `data-db-0`, `data-db-1`, and `data-db-2`, each 1Gi in size, all bound individually. If the Pod is rescheduled, it connects to its own individually named PVC and not a brand new PVC and I didn't specifically test a reschedule-and-reattach, but it can be inferred from the connection between the name and the ordinal number, and is a direct extension of the independence demonstrated by A1's self-healing test already showed PVC-and-Pod-lifecycle-independence in the simpler single-replica case.


The thing that genuinely caught me off guard about this: scaling to 3 replicas exceeded my own A1 ResourceQuota, not once but twice, from two different angles.

```text
persistentvolumeclaims "data-db-2" is forbidden: exceeded quota: ns-quota,
requested: persistentvolumeclaims=1, used: persistentvolumeclaims=2, limited: persistentvolumeclaims=2
```

The value of ` persistentvolumeclaims` was set to 4, but `db-2` was not present; this is because the StatefulSet controller does not monitor the ResourceQuota, hence fixing the ResourceQuota will not cause it to try again by itself; scaling down and back up is what causes it to try again. This brought me to the second barrier:

```text
pods "db-2" is forbidden: exceeded quota: ns-quota,
requested: limits.memory=256Mi, used: limits.memory=832Mi, limited: limits.memory=1Gi
```

The actual value of the peak was calculated and not just estimated: `db` with 3 replicas and `backend` and `frontend` gives us a peak of 1850m CPU / 1088Mi memory in a scaling experiment. `limits.memory` was set to 1200Mi (so tight that there is no question about it being selected randomly), and `persistentvolumeclaims` to 4 (3 replicas + 1 extra). No changes were required for `limits.cpu`; the 2 in A1 already satisfied the 1850m peak.

<!-- ![Final quota, sized for the scaling demo's actual peak usage](evidence/02d-quota-final.png) -->

## 2.2 Ingress and Ingress Controllers

### 2.2.1 Ingress resource configuration

Whereas A1 used NodePort for frontend services, now frontend is exposed through a single Ingress resource taking care of routing and TLS. This is really what Ingress is meant for: one entry point rather than one NodePort for each application.


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

The worked example from the lecture notes employs `rewrite-target: /` annotation. I did not include it on purpose. `rewrite-target: /` annotation will reduce the matched path to `/` prior to forwarding – good for a backend expecting paths like `/`, not for me as my backend expects `/api/tasks`, `/api/status` etc. Using an example from the lecture notes without modification would render each API call useless due to rewrite of `/api/tasks` to `/`. I validated the assumptions of the example according to my backend prior to use.


Now frontend is exposed through the Ingress resource so there is no need for `frontend-svc` to have its own NodePort anymore.

![Ingress created with both hosts listed, frontend-svc now ClusterIP](evidence/05-ingress-created.png)

### 2.2.1.1 Basic routing rules

```bash
curl -sk https://tasktracker.local/api/status
curl -sk https://tasktracker.local/ | head -3
```

`/api/status` returned the backend's JSON and `/ `returned the frontend's HTML, same host and port, routed to different Services by path.


### 2.2.1.2 TLS termination


There is no actual domain name for the kind cluster, so I created a self-signed certificate for both hostnames and added it to a `Kubernetes.io/tls` secret:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tasktracker.key -out tasktracker.crt \
  -subj "/CN=tasktracker.local/O=dso202" \
  -addext "subjectAltName=DNS:tasktracker.local,DNS:api.tasktracker.local"
kubectl create secret tls tasktracker-tls --cert=tasktracker.crt --key=tasktracker.key -n dso202-assignment-01
```



Both `curl` tests used `https://`, along with `-k` to allow the use of the self-signed certificate (otherwise curl won’t even try connecting, which is the right behavior for an untrusted certificate). Encryption and decryption occur in the Ingress controller, whereas the frontend and backend pods behind the Ingress controller receive requests through plain old HTTP, without TLS.

![Path routing and TLS termination both working](evidence/06-ingress-routing-tls.png)

### 2.2.1.3 Name-based virtual hosting

Both `tasktracker.local` and `api.tasktracker.local` resolve to the same IP address (I put both into `/etc/hosts` to `127.0.0.1`) on my computer, but the routing is entirely different via Ingress - one gives access to the full application while another gives access only to the backend on the path `/`. Different routing based only on the Host header:

```bash
curl -sk https://tasktracker.local/api/status
curl -sk https://api.tasktracker.local/api/status
```

Both hostnames return the same backend JSON. This is exactly how it should be - `api.tasktracker.local` forwards all requests on `/*` to the backend so `/api/status` would reach the same place either way just using different rules.

![Same result from two different hostnames, proving separate virtual-host rules](evidence/07-ingress-virtualhost.png)

### 2.2.2 Setting up Ingress Controllers

#### 2.2.2.1 NGINX Ingress Controller

I installed this using kind's own dedicated manifest (not the generic cloud one), since it's built specifically to work with kind's `hostPort` setup rather than needing a real cloud LoadBalancer:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
```

It failed the first time around - `kubectl wait` timed out after 180 seconds. I did more than run it again - I looked into why it happened using `kubectl describe pod` and saw two issues in succession, neither of which is an actual problem:
- First, in the first few minutes, there was a benign "FailedMount: secret "ingress-nginx-admission" not found", which is a well-known issue in kind, when the controller Pod starts being scheduled a little bit earlier than webhook installation job creates its certificate (this solves itself),
- then it takes 2m54s to download the image, which actually exceeded 180 seconds, which caused the timeout.

![Controller confirmed Running and 1/1, IngressClass nginx registered](evidence/04-ingress-controller.png)

#### 2.2.2.2 Traefik Ingress Controller

I did not use Traefik in combination with NGINX since using two ingress controllers in one small cluster with one small application doesn't seem like a realistic scenario even to check off a box in the syllabus, so I will describe it below based on my knowledge of both and the lecture notes.


Both Traefik and NGINX Ingress Controller handle the exact same challenge - routing of external HTTP(S) traffic into the cluster at layer 7, but differ in certain aspects. Traefik is implemented in Go and includes native custom resources (`IngressRoute`, and other CRDs), as well as the support of the standard Kubernetes `Ingress` resource, which allows defining routes that are impossible to be defined in the vanilla `Ingress` resource spec and which doesn't require controller-specific annotations. Traefik provides a built-in dashboard to monitor live routing configuration and a native integration of the controller with Let's Encrypt certificates handling. Features available through annotations are similar in their implementation to NGINX's ones but have a different prefix (`traefik.ingress.kubernetes.io/...` vs `nginx.ingress.kubernetes.io/...`) - this is exactly what the notes mean when mentioning that annotations are controller-specific and never portable between controllers.

It becomes a little more critical right now to make a selection of which to use compared to last year. As a point noted in the lecture slides, the NGINX Ingress Controller that I've used in this project and that has been the most utilized version in history went into maintenance status as of 2026, meaning that there will be no future updates, patches or releases starting in March 2026. It was selected for this assignment because it is the one used in the lecture slides' working example and it is the most documented one, but I know that a true development team would have had to consider it versus Traefik or Gateway API.


### 2.2.3 Ingress annotations for controller-specific features

I made use of `nginx.ingress.kubernetes.io/limit-rps: "5"`, where each client IP is limited to make up to 5 requests per second. Since I wanted it to really get triggered, I decided to throw some load on it:

```bash
for i in $(seq 1 40); do curl -sk -o /dev/null -w "%{http_code}\n" https://tasktracker.local/api/status; done | sort | uniq -c
```

28 returned `200`, 12 returned `503`. The previous attempt with 10 requests turned out to be insufficient to trigger it at all — `limit_req` is tolerant of some bursts over the declared value, so some reasonable number of requests can pass through unimpeded. I have also verified the resulting NGINX configuration, as well as checking that my annotation has really generated a working `limit_req_zone` rather than me getting lucky with numbers.

![28 requests succeeded, 12 hit the rate limit once load was high enough](evidence/08-ingress-ratelimit.png)

## 2.3 Kubernetes RBAC

A1's Task 8 (which was the optional task) dealt with creating a single Role attached to a single ServiceAccount giving read-only access to a namespace. In contrast, this task deals with Roles versus ClusterRoles, aggregation specifically, as well as binding to all types of subjects described there - users, groups, and service accounts.

### 2.3.1 Roles and ClusterRoles

#### 2.3.1.1 Defining permissions for resources

I gave the backend its own dedicated ServiceAccount and Role, replacing the namespace's default ServiceAccount it was running as before (which the lecture notes specifically call out as something to avoid — permissions granted to the default SA are silently shared by everything in the namespace that doesn't ask for a different one):

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

I'll be honest about this one rather than inventing a justification: my backend doesn't currently call the Kubernetes API for anything, it's a REST server talking to Postgres. This Role and ServiceAccount exist to demonstrate the mechanism properly, not because the app needs it today - and I picked read-only access to Pods specifically because it sets up a clean, honest contrast in 2.3.3.2.


#### 2.3.1.2 Aggregated ClusterRoles



This was  very new mechanic I discovered. The `edit`, `view`, and `admin` ClusterRoles defined by Kubernetes are not fixed sets of permissions; they include a label selector and the API server merges all the ClusterRoles that match those labels. In order to show proof rather than just explain what happens here, I needed some resource that would not be covered by the `edit` role yet, but given how many resources are covered by the `edit` role, this required an actual CRD (`TaskTrackerBackup`; I will reuse this CRD for the next section as well — the CRD is guaranteed to have zero permissions initially).

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

Before constructing this, `pema` (assigned to the `edit` ClusterRole using a RoleBinding within my namespace) received `no` on testing whether she could create a `tasktrackerbackup`. As soon as the little ClusterRole above was applied, without anything whatsoever being changed regarding `edit`, the test showed `yes`. This time, I verified the process directly, not just the result:

```bash
kubectl get clusterrole edit -o jsonpath='{.aggregationRule}'
kubectl get clusterrole edit -o jsonpath='{.rules[?(@.apiGroups[0]=="dso202.example.com")]}'
```

The first line indicated the selector of `edit`, which was exactly the same as the name given to my little ClusterRole. The second indicated `tasktrackerbackups` already included in the rule set of `edit`. No one ever executed `kubectl edit clusterrole edit`. That was the whole idea behind the system.

![Before: edit can't touch the new CRD at all](evidence/18-edit-before-aggregation.png)
![After: edit can, immediately, plus the aggregationRule and merged rules proving why](evidence/19-edit-after-aggregation.png)

### 2.3.2 RoleBindings and ClusterRoleBindings

#### 2.3.2.1 Binding roles to users, groups, and service accounts

There is no `User` type in Kubernetes - "creating a user" involves issuing a trusted certificate and creating a Role bound to the subject inside that certificate. I issued such a user for myself:

```bash
openssl genrsa -out pema.key 2048
openssl req -new -key pema.key -out pema.csr -subj "/CN=pema/O=dso202-students"
```

then had the CSR signed by the internal CSR API of the cluster, using the very signer trusted by the API server for client authentification (`kubernetes.io/kube-apiserver-client`) — any other name would fail quietly:

```bash
kubectl apply -f pema-csr.yaml   # CertificateSigningRequest wrapping the base64'd CSR
kubectl certificate approve pema
```

`CN=pema` became my username, bound directly:

```bash
kubectl create rolebinding pema-reader --namespace=dso202-assignment-01 --role=namespace-reader --user=pema
```

Then I transitioned to the identity correctly, via an actual kubeconfig context, not via `--as=`, and checked via the same before/after check that A1's Task 8 had done, but extended somewhat:

```bash
kubectl config use-context pema-context
kubectl get pods          # works
kubectl get secrets       # Forbidden — not in the Role
kubectl get pods -n kube-system   # Forbidden — RoleBinding is namespace-scoped
kubectl get nodes         # Forbidden — cluster-scoped, a Role could never cover it anyway
```

That last error message was more informative than I expected — Kubernetes itself said `Forbidden ... at the cluster scope`, not just refusing generically.

![Working inside pema's own namespace, correctly Forbidden everywhere else](evidence/15-user-context-scoped.png)

For groups, I minted a second identity, `CN=classmate-demo`, in the same `O=dso202-students` group, and gave it **no personal binding at all** — only a group binding:

```bash
kubectl create rolebinding dso202-students-reader --namespace=dso202-assignment-01 --role=namespace-reader --group=dso202-students
```

Using `classmate-demo` context and doing `kubectl get pods` command was successful despite the fact that this particular user is not mentioned in any RoleBinding, but only the group to which he belongs.

![namespace-reader bound twice — once by user, once by group — and both work](evidence/16-group-role.png)
![classmate-demo reads pods through group membership alone](evidence/17-group-context-works.png)

However, both these binding entries are examples of RoleBinding, which are namespaced resources by default. In order to fulfill the part of "ClusterRoleBinding" in the title of this topic, I created another binding between `dso202-students` group and `view` ClusterRole:

```bash
kubectl get pods -n kube-system --as=classmate-demo   # Forbidden, before
kubectl create clusterrolebinding dso202-students-viewer-clusterwide --clusterrole=view --group=dso202-students
kubectl get pods -n kube-system --as=classmate-demo   # works, after
```

The first time that I did this was also a failure, and it is important to point out why: `--as=classmate-demo` does not impersonate the user's group – only the username. There is no list of users and groups in Kubernetes anywhere – it is only included in a certificate itself and this is exactly what is done automatically when I switch into a kubeconfig context. This means that the impersonation with `--as=` alone does not include this and I had to include `--as-group=dso202-students`:

```bash
kubectl get pods -n kube-system --as=classmate-demo --as-group=dso202-students
```

Now that the group was included, `classmate-demo` had visibility into every single control-plane Pod in `kube-system`, such as CoreDNS, etcd, API server, kube-proxy, everything - none of which could be reached previously. The `default` namespace returned "No resources found." That is not a failure, it's an empty namespace. In terms of permissions, it has passed, there's simply no resource to be listed there. This distinction (between Forbidden and empty) seems very much alike but actually means completely opposite things. And it took me to make a mistake in order to understand the difference.

This is the actual, practical difference between the two bindings - same group, forbidden via one and cluster-wide via another binding object.

![Before: Forbidden everywhere outside the namespace. After: cluster-wide access through the ClusterRoleBinding, once the group was actually included in the check](evidence/22-clusterrolebinding.png)

### 2.3.3 Service Accounts

#### 2.3.3.1 Creating and managing service accounts

`backend-sa` is created above (2.3.1.1). Attaching it to the backend Deployment needed one line:

```yaml
spec:
  template:
    spec:
      serviceAccountName: backend-sa
```

A Pod's ServiceAccount is only set when it's created, so changing this on an existing Deployment doesn't apply until the Pod restarts:

```bash
kubectl rollout restart deployment/backend
kubectl get pod -l tier=backend -o jsonpath='{.items[0].spec.serviceAccountName}'
```

confirmed `backend-sa`, not `default`.

![Backend Pod now running as its own dedicated ServiceAccount](evidence/09-backend-sa.png)

#### 2.3.3.2 Using service accounts for pod authentication

The quick way to check this is asking Kubernetes hypothetically what an identity *could* do:

```bash
kubectl auth can-i list pods --as=system:serviceaccount:dso202-assignment-01:backend-sa -n dso202-assignment-01   # yes
kubectl auth can-i get secrets --as=system:serviceaccount:dso202-assignment-01:backend-sa -n dso202-assignment-01 # no
```

![can-i checks for backend-sa: allowed on Pods, refused on Secrets](evidence/10-sa-can-i.png)

But I wanted to do it properly - actually running as that identity and firing requests to the actual API server with the very same token Kubernetes mounts to that Pod's filesystem, rather than performing some external validation. So I created a short-lived Pod running under the `backend-sa` service account and had it fetch its own token in order to authenticate:

```bash
kubectl run debug-as-backend --rm -i --image=curlimages/curl --restart=Never \
  --overrides='{"spec": {"serviceAccountName": "backend-sa"}}' \
  -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/dso202-assignment-01/pods
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/dso202-assignment-01/secrets
'
```

`HTTP 200` on Pods, `HTTP 403` on Secrets. This one is worth thinking about for a moment: this is the very same RBAC check happening on an actual request coming from within an actual Pod with its very own token mounted to the filesystem. And a good demonstration of the difference between how the backend gets its database password (injected as environment variable from a Secret when starting a container) and its own API identity (which doesn't get anything from Secrets whatsoever).

![Real API request, from inside a Pod, using its own mounted SA token](evidence/11-sa-pod-auth.png)

## 2.4 Kubernetes Operators

### 2.4.1 Operator pattern

The Operator Pattern involves encapsulating operational knowledge specific to an application, for example how to do failover, backups, upgrades for a particular software application, within a controller that is monitoring a Custom Resource and driving the actual state of the cluster to be in line with it, using the exact same reconcile loop concept that all the built-in Kubernetes controllers work on.

#### 2.4.1.1 Custom Resources and Custom Resource Definitions

The one I've done for my application is called `TaskTrackerBackup` and shows the structure of a possible future object used for backing up the task tracker database - that’s the real CRD:

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

Then a real instance of it:

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

What I really meant to prove was that a CRD on its own does nothing. `kubectl apply` and `kubectl get` treat it as if it were a native resource type - but:


```bash
kubectl describe tasktrackerbackup nightly-backup   # Status: (empty), Events: <none>
kubectl get pods,jobs,cronjobs                      # nothing backup-related, anywhere
```

Despite the fact that it explicitly says in the spec in plain English "run at 2am daily," nothing runs at 2am, since nobody in the cluster is watching `TaskTrackerBackup` resources. And even after leaving the experiment running a bit, the status field is still empty - not because of some delay, but because there is no controller whatsoever.

![CRD stored and readable like any built-in object, but completely inert — no controller watching it](evidence/21-crd-no-controller.png)

#### 2.4.1.2 Operator lifecycle management

After creating a working Operator, it will still need to be installed, upgraded, and permissioned just like any other workload; in some environments (specifically Red Hat OpenShift), this process is managed using a different software called Operator Lifecycle Manager (OLM). I have not used OLM in this case, because it represents another separate system for working with Operators, which was mentioned in the lecture notes only as something that we should know about but is not required for this particular unit. I can show, however, the very stage which OLM handles - my TaskTrackerBackup CRD, with no controller watching it  is exactly where a real Operator starts its installation process from.


### 2.4.2 Creating custom operators

#### 2.4.2.1 Operator SDK

Operator SDK (Kubebuilder) will take care of generating the CRD code structure, the watching/informing/workqueuing plumbing, and the RBAC configurations that the Operator requires, so the author only writes the reconciliation code. I did not use it as creating an actual Operator with it was not in the scope of this unit as per the lecture notes. However, it is directly related to what I have created: The aggregated ClusterRole in section 2.3.1.2 is precisely the kind of configuration that the Operator SDK would have created for a real `TaskTrackerBackup` Operator. I created it by hand to understand how it works.

#### 2.4.2.2 Writing controllers for custom resources

I didn't write a real controller, but I can describe precisely what one for `TaskTrackerBackup` would need to do, based on the reconcile loop from the lecture notes:

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

What the notes say for sure, and what in fact makes perfect sense after giving it some thought: this must be a level-based reconciliation, where "what does the spec require right now" is compared to "what is actually present right now" rather than to "what has specifically changed." The `nightly-backup` object I have sits there with an empty status as long as I let it – a real controller has to be able to withstand a restart, to completely skip an update or to clear its entire cache and still reach the right status on the next attempt. "What changed" is precisely what will break when the controller starts working at an incorrect time.

### 2.4.3 Examples of popular operators

This ties right back into the point I've been making in section 2.1 of using only one `db` replica, since the basic `postgres` image isn't able to coordinate multiple replicas of itself, something I proved directly in the independent data test. The actual piece that bridges the gap is a Postgres operator - there are two common options: **CloudNativePG** or the **Zalando Postgres Operator** -. Behind the scenes, it's actually managing a StatefulSet, the very same object I created by hand in 2.1, but it has the application knowledge that a StatefulSet does not: picking the leader replica out of the set, configuring streaming replication to ensure that the replicas are actually kept in sync, failover in case the leader goes down, and backups that happen automatically, something my simple `TaskTrackerBackup` CRD was pretending to do but which doesn't actually use an operator. The **Prometheus Operator** is another famous example of an operator, which manages Prometheus and Alertmanager through its own CRDs (`Prometheus`, `ServiceMonitor`).

## Problems encountered and how I actually worked through them


- **`FailedMount` and a slow image pull by the Ingress controller.** 2.2.2.1 - neither were issues, both got fixed once I reviewed the events instead of simply repeating the command.
- **My A1 Quota was reached when scaling up the StatefulSet, twice.** 2.1.4 - firstly, PVC quota, then memory limit, and a forced reconciliation via scale-down/scale-up was needed because the StatefulSet controller does not observe its quota.
- **`crd/` directory did not exist when I initially attempted to create a CRD file.** `mkdir -p crd` solved the issue, which seems like a minor thing to pay attention to, but one of those errors worth reading.
- **I tested `api.tasktracker.local/status` before discovering that the actual route is `/api/status`.** I found out the issue myself from the "Cannot GET /status" error message - a simple mistake, not a routing problem.
- **New cluster, old namespace in kubectl.** After rebuilding a cluster for Ingress, `kubectl get pods` returned an empty list because the `set-context --current --namespace=...` trick did not persist through a new cluster.

## Limitations
- The database has not been turned into a 3-replica StatefulSet in the running version, but its behavior has been shown deliberately then scaled down, because a real 3-replica setup would require an actual operator (2.4.3).
- TLS certificates are self-signed, because there is no real domain in the kind cluster - a real deployment would have cert-manager set up and a proper certificate authority, which is specifically mentioned in the lecture notes as such.
- `TaskTrackerBackup` is a CRD without a controller. This is a design choice for the task (2.4.1.1), not something that I have not had enough time to implement - the fact that a controller is not implemented is explicitly stated in the lecture notes to be out of scope.
- The read-only RBAC permission for Pods is only for demonstration purposes (2.3.1.1) and is not actually used in the application today.

