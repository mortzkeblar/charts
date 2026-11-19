# Changelog

All notable changes to this chart are documented in this file.

## [0.3.0]

First release of this fork of [usememos/helm](https://github.com/usememos/helm).

### Changed
- **BREAKING**: `image.repo` + `image.imageName` replaced by `image.repository`
  (`ghcr.io/usememos/memos`); `image.tag` now defaults to the chart `appVersion`
  instead of `latest`.
- **BREAKING**: `persistence.existPersistClaim` renamed to `persistence.existingClaim`.
- `persistence.enabled` defaults to `true`, and `persistence.storageClass` to the
  cluster default instead of `local`.
- The container always listens on 5230; `service.port` only changes the Service port.
  Before, changing `service.port` made memos listen on a port the container did not expose.
- Deployment uses the `Recreate` strategy with a ReadWriteOnce volume, so updates no
  longer hang waiting for the volume.
- Pods restart when `config.secretEnv` changes (checksum annotation).
- Resources: no CPU limit by default (avoids throttling), lower CPU request.
- HPA `maxReplicas` default lowered to 3.
- Helm test pins `busybox:1.37` and cleans up after itself.

### Security
- **BREAKING**: runs as UID/GID 10001, the non-root user of the memos image
  (was 1000). `fsGroup` fixes the ownership of existing volumes on the next start.
- Pod Security Standards `restricted` by default: `seccompProfile: RuntimeDefault`,
  `readOnlyRootFilesystem: true` (with an `emptyDir` on `/tmp`), `runAsGroup`.
- `enableServiceLinks: false`, and `automountServiceAccountToken` on the pod.
- Optional NetworkPolicy (`networkPolicy.*`): ingress only on the HTTP port, optionally
  restricted to given peers, and optional egress lockdown with DNS allowed.
- `config.existingSecret` loads credentials (e.g. `MEMOS_DSN`) from an existing Secret.
- The Helm test pod is non-root with a read-only root filesystem.

### Added
- `podLabels`.
- Labels on the Secret.
- Documented values and a values table in the README.

### Fixed
- HTTPRoute rules without `matches` rendered invalid YAML.

### Removed
- `httpRoute.tls` (HTTPRoute has no TLS settings; TLS is configured on the Gateway).
- Makefile publishing to the upstream GHCR registry, and upstream GitHub workflows.

## [0.2.1] - 2025-12-07

### Fixed
- Eliminate tabs in Chart.yaml to fix yaml errors

## [0.2.0] - 2025-11-23

### Changed
- **BREAKING**: Updated minimum Kubernetes version requirement to 1.19+
- Updated memos application version from 0.14.3 to 0.25.2
- Upgraded HPA API from `autoscaling/v2beta1` to `autoscaling/v2`
- Simplified Ingress to use only `networking.k8s.io/v1`
- Updated HPA metrics structure to match v2 API specifications

### Added
- Security best practices enabled by default (non-root UID 1000, all capabilities
  dropped, privilege escalation disabled)
- Default resource limits and requests
- README requirements, security and resource sections
- CHANGELOG.md

### Removed
- Support for Kubernetes < 1.19 and deprecated API versions

## [0.1.0] - 2023-09-10

### Added
- Initial release of the Memos Helm chart (memos 0.14.3): Deployment, Service,
  Ingress, PVC and HPA
