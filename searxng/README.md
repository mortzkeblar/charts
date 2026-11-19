# searxng Helm chart

This is a fork of [techpipe-io/searxng-helm-chart](https://github.com/techpipe-io/searxng-helm-chart)
(Apache 2.0), adapted to run under Kubernetes Pod Security Standards
`restricted` on a cluster with no persistent storage. See the [Fork](#fork)
section below for the full list of changes against upstream, and
[NOTICE](./NOTICE) for attribution.

## Included features

- SearXNG Deployment and Service
- Optional Valkey as an official upstream dependency ([valkey-io/valkey-helm](https://github.com/valkey-io/valkey-helm))
- Writable runtime config volume with generated `settings.yml`
- Optional extra config files such as `limiter.toml` and `favicons.toml`
- Optional Ingress
- Optional Gateway API `HTTPRoute`
- Optional custom CA certificates mount
- `SEARXNG_SECRET` from an existing Secret, a literal value, or chart-generated
- Pod Security Standards `restricted` compliant by default (pod, container,
  and initContainer security contexts)

## Defaults

- 1 replica
- Pod Security Standards `restricted`: non-root UID/GID 977 (matches the
  `searxng/searxng` image's built-in user), all capabilities dropped,
  `readOnlyRootFilesystem: true`, `seccompProfile: RuntimeDefault`
- No persistent storage anywhere — every volume is `emptyDir`
- Bundled Valkey disabled (`valkey.enabled: false`)
- `secret.create: false` — you must configure `secret.existingSecret`,
  `secret.value`, or opt into `secret.create: true`, or the render fails (see
  [Secrets](#secrets))
- `server.base_url: ""` (autodetected behind a reverse proxy)
- `general.enable_metrics: false` (`/stats` is not exposed by default)
- `server.method=GET`
- `server.image_proxy=true`
- Ingress and Gateway API disabled by default

## Install with Helm

```bash
helm upgrade --install searxng oci://ghcr.io/mortzkeblar/charts/searxng \
  --version 0.1.0 --namespace search --create-namespace \
  --set secret.create=true
```

From a checkout of this repository:

```bash
helm dependency build ./searxng
helm template searxng ./searxng --set secret.create=true
```

## Main values

### Runtime environment

- `env.values`
- `env.secretValues`
- `env.existingSecrets`
- `env.existingConfigMaps`

`env.values` and `env.secretValues` are the catch-all mechanisms for additional
`SEARXNG_*`, `GRANIAN_*`, or other container environment variables.

### SearXNG config

The chart generates `settings.yml` from:

```yaml
config:
  useDefaultSettings: true
  settings: {}
```

Extra non-secret config files go into `config.files`. Extra secret config
files go into `config.secretFiles`.

Examples:

```yaml
config:
  files:
    limiter.toml: |
      [botdetection.ip_lists]
      block_ip = []
```

```yaml
config:
  secretFiles:
    settings.yml: |
      use_default_settings: true
      server:
        base_url: https://search.example.com/
        secret_key: replace-me
```

If `config.secretFiles["settings.yml"]` is provided, it overrides the
generated `settings.yml`.

### Secrets

`SEARXNG_SECRET` needs exactly one of three sources — the chart fails to
render (with a message listing them) if none is configured:

Bring your own existing Secret:

```yaml
secret:
  existingSecret: searxng-runtime
  existingSecretKey: SEARXNG_SECRET
```

A literal, deterministic value (still ends up inside a chart-generated
Secret, not inline in the Deployment):

```yaml
secret:
  value: replace-me
```

Or let the chart generate one:

```yaml
secret:
  create: true
```

Only use `create: true` without `value` for throwaway/dev installs. Without a
literal `value`, it falls back to a random value regenerated on every
`helm template`/`helm install` — the rendered output is **not deterministic**,
which breaks GitOps tools that diff manifests (e.g. ArgoCD shows permanent
`OutOfSync` and rotates the pod on every sync) and invalidates
sessions/limiter tokens on every rollout.

### Storage

There is no persistence support in this chart: `config-runtime` (`/etc/searxng`),
`cache` (`/var/cache/searxng`), and `tmp` (`/tmp`, required by
`readOnlyRootFilesystem: true`) are all plain `emptyDir` volumes, unconditionally.
There is no values key that turns any of them into a PersistentVolumeClaim.

Their usage counts against the pod's ephemeral storage. If you need to bound
it, set `resources.limits.ephemeral-storage` — there is no per-volume
`sizeLimit` key.

`extraVolumes`/`extraVolumeMounts` are **only** for mounting additional
volumes under names that don't collide with `config-runtime`, `cache`, or
`tmp`. Do not use them to redefine those three: a second `spec.volumes` entry
with the same `name` makes the Kubernetes API reject the manifest outright.

`init-config` (an initContainer) copies `config.files`/`config.secretFiles`
into the `config-runtime` emptyDir before the main container starts; this
pattern is unchanged from upstream.

Ownership of these `emptyDir` volumes is handled entirely by
`podSecurityContext.fsGroup` (977, matching the image's built-in `searxng`
user). The upstream `FORCE_OWNERSHIP` environment variable was removed from
this fork: its `chown` branch in the image's entrypoint only runs when the
process is root, which never happens under `runAsNonRoot: true`. You may see a
harmless `WARNING: ... not owned by "searxng:searxng"` line at container
startup — it's cosmetic, `fsGroup` already grants the process write access via
group permissions.

### Valkey

Valkey is **not** bundled inline — it's the official
[valkey-io/valkey-helm](https://github.com/valkey-io/valkey-helm) chart,
declared as a conditional dependency in `Chart.yaml`. It's required if you
enable `config.settings.server.limiter` or `config.settings.server.public_instance` —
SearXNG itself won't start correctly without one in that case. This chart
does not check that for you at render time; it's on you to pair
`config.settings.server.limiter: true` with `valkey.enabled: true` or
`externalValkey.*`.

`valkey.enabled` (bundled subchart) and `externalValkey.*` (URL you manage
yourself) are mutually exclusive — set at most one.

#### Bundled Valkey

```yaml
valkey:
  enabled: true
  fullnameOverride: vk # recommended: see note below
```

Setting `valkey.fullnameOverride` explicitly is recommended. Without it, this
chart has to mirror the Valkey subchart's own (unexported) name-generation
logic to compute `SEARXNG_VALKEY_URL` — it's covered by this chart's tests,
but any future change to that logic in `valkey-io/valkey-helm` would need a
matching change here.

Bundled Valkey with ACL auth (password is inline/plaintext, matching what the
`aclUsers` field itself expects):

```yaml
valkey:
  enabled: true
  fullnameOverride: vk
  auth:
    enabled: true
    aclUsers:
      default:
        permissions: "~* &* +@all"
        password: "changeme"
```

This renders `SEARXNG_VALKEY_URL=valkey://default:changeme@vk:6379/0`.
SearXNG's Valkey client (`searx/valkeydb.py`) uses `valkey.Valkey.from_url()`,
and SearXNG's own docs
([`settings_valkey.rst`](https://github.com/searxng/searxng/blob/master/docs/admin/settings/settings_valkey.rst))
document exactly this `valkey://[[username]:[password]]@host:port/db` form, so
username/password auth is a real, app-supported feature, not just a
Valkey-side one.

This fork only wires up the `default` ACL user into `SEARXNG_VALKEY_URL`.
Multi-user ACLs, `valkey.auth.usersExistingSecret`, or TLS need a manually-set
`env.secretValues.SEARXNG_VALKEY_URL` (or `externalValkey.urlSecret`) instead.

#### External Valkey

Literal URL:

```yaml
valkey:
  enabled: false
externalValkey:
  url: valkey://my-valkey.default.svc.cluster.local:6379/0
```

Or reference a secret containing a full URL:

```yaml
valkey:
  enabled: false
externalValkey:
  urlSecret:
    name: searxng-runtime
    key: SEARXNG_VALKEY_URL
```

### Custom CA certificates

Inline certificates:

```yaml
caCertificates:
  files:
    corp-root.crt: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
```

Or mount an existing ConfigMap or Secret:

```yaml
caCertificates:
  existingConfigMap: corp-ca
```

## Ingress example

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: search.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: search-example-com-tls
      hosts:
        - search.example.com
config:
  settings:
    server:
      base_url: https://search.example.com/
```

## Gateway API example

The chart creates an `HTTPRoute`, not a `Gateway`.

```yaml
ingress:
  enabled: false
gateway:
  enabled: true
  parentRefs:
    - name: public
      namespace: infra
      sectionName: https
  hostnames:
    - search.example.com
config:
  settings:
    server:
      base_url: https://search.example.com/
```

## Fork

Changes against
[techpipe-io/searxng-helm-chart](https://github.com/techpipe-io/searxng-helm-chart):

- Added Pod Security Standards `restricted` support: `podSecurityContext`,
  `securityContext`, and a separate `initContainerSecurityContext` (new values
  keys, previously no security context existed at any level).
  `automountServiceAccountToken: false` at the pod level.
- Removed all persistent storage: `templates/pvc.yaml` is gone, the entire
  `persistence.*` values block is gone, and `config-runtime`/`cache`/`tmp` are
  unconditional `emptyDir` volumes. Added a `tmp` emptyDir (required by
  `readOnlyRootFilesystem: true`).
- Added `strategy` (default `RollingUpdate`) for the Deployment.
- Removed `env.forceOwnership`/`FORCE_OWNERSHIP` — inert once the container is
  forced non-root (see [Storage](#storage) above).
- Replaced the inline Valkey Deployment/Service/PVC/Secret with the official
  [valkey-io/valkey-helm](https://github.com/valkey-io/valkey-helm) chart as a
  conditional dependency. `valkey.*` in `values.yaml` is now a set of overrides
  for that subchart (`enabled`, `fullnameOverride`, `dataStorage.enabled`,
  `valkeyConfig`, `auth`), not the inline chart's own values. The old
  `valkey.externalUrl`/`externalUrlSecret` moved to a new top-level
  `externalValkey.{url,urlSecret}` block.
- Switched all three probes from `tcpSocket` to `httpGet` against `/healthz`.
- Reset chart `version` to `0.1.0`; `image.tag` now defaults to `""` and falls
  back to `.Chart.AppVersion`.
- Removed the upstream Artifact Hub signing key annotation and the Valkey
  entries from `artifacthub.io/images`/`keywords` (Valkey is now a dependency,
  not an image this chart controls directly).
- `secret.create` now defaults to `false`: with no `existingSecret` or `value`
  configured, the chart fails to render instead of silently generating a
  non-deterministic `SEARXNG_SECRET` on every render (breaks GitOps diffing).
  See [Secrets](#secrets).
- `config.settings.server.base_url` defaults to `""` (autodetect from
  reverse-proxy headers) instead of a placeholder `http://searxng.local/`.
- `config.settings.general.enable_metrics` defaults to `false` — `/stats` and
  `/stats/errors` are not exposed by default.
- `ingress.hosts` defaults to `[]` instead of a placeholder `searxng.local`.
- Added a dedicated `initContainer.image`/`initContainer.resources`: the
  `init-config` initContainer no longer borrows `testConnection.image`, since
  that's load-bearing on the pod's startup path and `testConnection.enabled: false`
  must not remove it.
- Fully qualified every image reference with its registry
  (`docker.io/searxng/searxng`, `docker.io/library/busybox`).
- Consolidated `image.pullSecrets` into a top-level `global.imagePullSecrets`,
  so the `valkey` subchart inherits the same list via Helm's built-in global
  value propagation instead of needing its own copy.
- `env:` on the `searxng` container is now omitted entirely when there are no
  entries, instead of rendering as `env: null`.
- Added `app.kubernetes.io/version` (from `.Chart.AppVersion`) to the common
  labels.
- The `helm test` Pod now carries the same `podSecurityContext`/`securityContext`
  as the Deployment, `automountServiceAccountToken: false`, and minimal
  `resources` — it was previously rejected outright under PSS `restricted`
  admission. Its probe target also moved from `/` to `/healthz`.
- `gateway` (HTTPRoute) is disabled by default with a generic `parentRefs` and no
  hostnames, like `ingress`.
- Added optional NetworkPolicies (`networkPolicy.*`): SearXNG accepts traffic only
  on its HTTP port (optionally from given peers) with optional egress lockdown, and
  the bundled Valkey accepts connections only from SearXNG.

## Attribution

This chart is a derivative work of
[techpipe-io/searxng-helm-chart](https://github.com/techpipe-io/searxng-helm-chart)
(Apache License 2.0). See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).

The `valkey` dependency ([valkey-io/valkey-helm](https://github.com/valkey-io/valkey-helm))
is licensed under BSD-3-Clause, a different license from this chart's
Apache-2.0. See [NOTICE](./NOTICE) for details.
