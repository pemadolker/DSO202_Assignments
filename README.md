# DSO202 Assignments

**Student:** Pema Dolker  
**Student ID:** 02230294  
**Module:** DSO202: Scaling, Orchestration, Monitoring & Observability

This repository holds my DSO202 assignments. All of them deploy the same three-tier Task Tracker application (nginx frontend, Node.js backend, PostgreSQL database) to a local kind cluster. Each assignment has its own folder and its own README with the explanation and the screenshots.

| Folder | Assignment | Topic |
|---|---|---|
| [assignment-1](assignment-1/) | Assignment 1 | Three-tier deployment with plain Kubernetes manifests (Unit I) |
| [assignment-2](assignment-2/) | Assignment 2 | Assignment 1 extended with StatefulSets, Ingress, RBAC and Operators (Unit II) |
| [assignment-3](assignment-3/) | Assignment 3 | Assignment 1 packaged with Kustomize and Helm |

## Note on the container images

All three assignments use `pdolker/dso202-{frontend,backend,db}:1.0` instead of the tutor's `sarojsanyasi/dso202-{frontend,backend,db}:1.0`. The tutor's images are published for `linux/arm64` only, and my laptop is `amd64`, so I rebuilt them from the provided source code without any changes. This was discussed with and approved by the tutor.

My images are built for `amd64` only. On an Apple Silicon (arm64) machine, the tutor's images should be used instead. Nothing else needs to change, because both sets of images use the same tag, ports and environment variables.

**Assignment 1 and Assignment 2:** change the `image:` lines marked `# TEMP` to `sarojsanyasi/...`. In A1 these are in the three Deployment files. In A2 they are in the backend and frontend Deployments and in `database/statefulset.yaml`.

**Assignment 3, Kustomize:** add `newName` to the three entries in `assignment-3/kustomize/base/kustomization.yaml`. Both overlays pick up the change.

```yaml
images:
  - name: pdolker/dso202-frontend
    newName: sarojsanyasi/dso202-frontend
    newTag: "1.0"
  - name: pdolker/dso202-backend
    newName: sarojsanyasi/dso202-backend
    newTag: "1.0"
  - name: pdolker/dso202-db
    newName: sarojsanyasi/dso202-db
    newTag: "1.0"
```

**Assignment 3, Helm:** no file changes are needed. Add three flags to the install command:

```bash
--set images.frontend.repository=sarojsanyasi/dso202-frontend \
--set images.backend.repository=sarojsanyasi/dso202-backend \
--set images.database.repository=sarojsanyasi/dso202-db
```

## Before running

- A kind cluster with host port 30080 mapped to the node is needed (as in Practical 1). Assignment 2 also needs ports 80 and 443 mapped and the NGINX Ingress controller; its README has the kind config and the install steps.
- Assignment 3 does not commit any credentials. The files `db.env` (Kustomize) and `secrets.yaml` (Helm) are created from the `.example` files, as described in section 9 of the Assignment 3 README.
- On macOS, Docker Desktop does not route to the kind node's IP address. NodePorts other than 30080 should be reached with `kubectl port-forward` instead.