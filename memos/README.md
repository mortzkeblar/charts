# memos Helm chart

Deploys [Memos](https://usememos.com), a self-hosted, privacy-first note-taking service.

This chart is a fork of [usememos/helm](https://github.com/usememos/helm). See the
[CHANGELOG](CHANGELOG.md) for the changes made in this fork.

## Requirements

- Kubernetes 1.25+
- Helm 3.8+
- Gateway API CRDs, only when `httpRoute.enabled` is true

## Install

```bash
helm install memos ./memos --namespace memos --create-namespace
```

By default memos uses SQLite and stores its data in a 10Gi PersistentVolumeClaim on the
default StorageClass.

## Configuration

### Environment variables

Memos is configured through environment variables
([reference](https://usememos.com/docs/configuration)):

```yaml
config:
  env:
    MEMOS_INSTANCE_URL: https://memos.example.com
  # Stored in a Secret created by the chart
  secretEnv: {}
```

`MEMOS_PORT` is set by the chart and should not be overridden.

### External database

To use PostgreSQL (or MySQL) instead of SQLite:

```yaml
config:
  env:
    MEMOS_DRIVER: postgres
  # Secret with a MEMOS_DSN key, e.g. postgresql://memos:password@postgres:5432/memos
  existingSecret: memos-db
```

`config.secretEnv` also works, but puts the DSN in your values.

Only with an external database can you run more than one replica or enable
`autoscaling`.

### Persistence

| Setting | Result |
|---|---|
| `persistence.enabled: true` (default) | A new PVC sized `persistence.size` |
| `persistence.existingClaim: my-pvc` | Uses an existing PVC |
| `persistence.enabled: false` | `emptyDir`: data is lost when the pod is recreated |

With a ReadWriteOnce volume the Deployment uses the `Recreate` strategy, so an
upgrade stops the old pod before starting the new one.

### Exposing memos

Use either an Ingress:

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: memos.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: memos-tls
      hosts: [memos.example.com]
```

or a Gateway API HTTPRoute:

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway
      namespace: gateway-system
      sectionName: https
  hostnames:
    - memos.example.com
```

## Security

The defaults comply with the Pod Security Standards `restricted` profile:

- Non-root UID/GID 10001 (the image's own user), `seccompProfile: RuntimeDefault`
- No privilege escalation, all capabilities dropped, read-only root filesystem
  (data lives in `/var/opt/memos`, scratch space in an `emptyDir` on `/tmp`)
- No ServiceAccount token and no Service environment variables in the pod

To limit network access, enable the NetworkPolicy:

```yaml
networkPolicy:
  enabled: true
  # Only the gateway / ingress controller may reach memos
  ingressFrom:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: gateway-system
  egress:
    # Off by default: memos needs egress for webhooks, S3 and link previews
    enabled: true
    rules:
      - to:
          - podSelector:
              matchLabels:
                app.kubernetes.io/name: postgresql
        ports:
          - port: 5432
            protocol: TCP
```

## Values

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `1` | Replicas; keep 1 with SQLite |
| `image.repository` | `ghcr.io/usememos/memos` | Image repository |
| `image.tag` | `""` | Image tag; defaults to the chart `appVersion` |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `imagePullSecrets` | `[]` | Registry pull secrets |
| `config.env` | `{}` | Plain environment variables |
| `config.secretEnv` | `{}` | Sensitive environment variables, stored in a Secret |
| `config.existingSecret` | `""` | Existing Secret loaded as environment variables |
| `persistence.enabled` | `true` | Use a PVC for `/var/opt/memos` |
| `persistence.existingClaim` | `""` | Existing PVC to use |
| `persistence.storageClass` | `""` | StorageClass; empty uses the default |
| `persistence.accessMode` | `ReadWriteOnce` | PVC access mode |
| `persistence.size` | `10Gi` | PVC size |
| `serviceAccount.create` | `true` | Create a ServiceAccount |
| `serviceAccount.automount` | `false` | Mount the ServiceAccount token |
| `podAnnotations` / `podLabels` | `{}` | Extra pod metadata |
| `podSecurityContext` | non-root 10001, seccomp RuntimeDefault | Pod security context |
| `securityContext` | no privilege escalation, no capabilities, read-only rootfs | Container security context |
| `enableServiceLinks` | `false` | Inject Service environment variables |
| `networkPolicy.*` | disabled | NetworkPolicy (ingress peers, optional egress lockdown) |
| `service.type` / `service.port` | `ClusterIP` / `5230` | Service |
| `ingress.*` | disabled | Ingress |
| `httpRoute.*` | disabled | Gateway API HTTPRoute |
| `resources` | 50m/128Mi requests, 512Mi memory limit | Container resources |
| `autoscaling.*` | disabled | HorizontalPodAutoscaler |
| `nodeSelector` / `tolerations` / `affinity` | empty | Scheduling |

## Upgrading from usememos/helm 0.2.x

- `image.repo` + `image.imageName` → `image.repository`
- `persistence.existPersistClaim` → `persistence.existingClaim`
- `persistence.enabled` now defaults to `true`: set it to `false` explicitly if you
  relied on `emptyDir`.
- The pod runs as UID/GID 10001 instead of 1000; `fsGroup` re-owns the volume on the
  first start. Keep the old IDs by overriding `podSecurityContext`.
