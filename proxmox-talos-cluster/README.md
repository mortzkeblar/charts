# proxmox-talos-cluster

Helm chart that declares a Kubernetes cluster running [Talos Linux](https://www.talos.dev/)
on [Proxmox VE](https://www.proxmox.com/), managed by [Cluster API](https://cluster-api.sigs.k8s.io/).

It renders the Cluster API objects only; the providers on the management cluster
create the VMs and bootstrap Talos.

```
Cluster ─┬─ ProxmoxCluster                  infrastructure: Proxmox nodes, IP pool, DNS
         ├─ TalosControlPlane ── ProxmoxMachineTemplate
         └─ MachineDeployment (per pool) ─┬─ ProxmoxMachineTemplate
                                          ├─ TalosConfigTemplate
                                          └─ MachineHealthCheck
```

## Requirements

A management cluster with these providers installed:

| Provider | Role |
|---|---|
| Cluster API core | `cluster.x-k8s.io/v1beta2` |
| [CAPMOX](https://github.com/ionos-cloud/cluster-api-provider-proxmox) | infrastructure (`v1alpha2`) |
| [CABPT](https://github.com/siderolabs/cluster-api-bootstrap-provider-talos) | bootstrap (`v1alpha3`) |
| [CACPPT](https://github.com/siderolabs/cluster-api-control-plane-provider-talos) | control plane (`v1alpha3`) |

Plus a Proxmox VM template with a Talos nocloud image, ideally built with the
`qemu-guest-agent` extension (otherwise set `machine.checks.skipQemuGuestAgent: true`).

## Usage

```bash
helm install my-cluster oci://ghcr.io/mortzkeblar/charts/proxmox-talos-cluster \
  --version 0.1.0 -n clusters --create-namespace -f my-values.yaml
```

Minimum values:

```yaml
cluster:
  controlPlaneEndpoint:
    host: 192.168.1.10        # API VIP, outside the IP pool
proxmox:
  dnsServers: [192.168.1.1]
  ipv4Pool:
    addresses: [192.168.1.11-192.168.1.30]
    gateway: 192.168.1.1
controlPlane:
  machine:
    templateID: 100           # VMID of your Talos template
workers:
  defaults:
    machine:
      templateID: 100
```

With the defaults you get 3 control plane nodes, one pool of 2 workers, Flannel,
kube-proxy and a MachineHealthCheck per pool. See
[`examples/homelab.yaml`](examples/homelab.yaml) for a fuller setup: Cilium without
kube-proxy, Talos CCM, Longhorn V2, OIDC, template selection by tag, autoscaling and
a tainted pool.

## Values

The full reference with defaults lives in [`values.yaml`](values.yaml). Overview:

| Key | Description |
|---|---|
| `cluster.name` | Cluster name; every object is named after it (default: release full name) |
| `cluster.kubernetesVersion` | Kubernetes version, without `v` |
| `cluster.paused` | Pause reconciliation of the whole cluster |
| `cluster.controlPlaneEndpoint` | API address (Talos VIP) and port |
| `cluster.network` | Pod and service CIDRs, service domain |
| `cluster.cni.name` / `cluster.kubeProxy.enabled` | CNI installed by Talos and kube-proxy toggle |
| `proxmox.allowedNodes`, `.credentialsRef` | Where machines may run, and per-cluster API credentials |
| `proxmox.dnsServers`, `.ipv4Pool`, `.ipv6Pool` | Machine networking (IPAM) |
| `talos.version`, `.hostnameSource` | Talos config version and where node hostnames come from |
| `talos.install`, `.kubelet`, `.timeServers` | Settings for every node |
| `controlPlane.machine` | VM shape for control plane nodes |
| `controlPlane.vip`, `.oidc`, `.talosAPIAccess`, `.apiServer` | Control plane features |
| `controlPlane.rolloutStrategy` | How control plane machines are replaced |
| `workers.defaults` | Defaults for every pool: `machine`, `replicas`, labels, taints, `autoscaling`, `rollout`, `deletion`, `healthCheck` |
| `workers.pools[]` | Worker pools; each entry is deep-merged over `workers.defaults` |
| `workers.sysctls`, `.kernelModules`, `.kubeletExtraMounts` | Node tuning for every worker |
| `controlPlane.extraPatches` / `workers.extraPatches` | Extra Talos patches (YAML strings) |

### Machine shape

`controlPlane.machine` and `workers.defaults.machine` (and each pool's `machine`) share
one layout: `templateID` or `templateSelector`, `sourceNode`, `allowedNodes`, `storage`,
`pool`, `tags`, `cpu`, `memoryMiB`, `disk`, `clone`, `network` (bridge, VLAN, MTU, extra
NICs), `vmIDRange` and `checks`.

### Health checks

Every pool gets a MachineHealthCheck (`healthCheck.enabled`). By default a machine is
replaced when its node is not Ready for 5 minutes, or never joins within 10 minutes, and
only while at least one machine of the pool is healthy. Tune it with
`unhealthyNodeConditions`, `unhealthyMachineConditions` and `remediation.triggerIf`
(e.g. `{unhealthyLessThanOrEqualTo: "40%"}`), or hand remediation to an external
controller with `remediation.templateRef`.

### Autoscaling

With `autoscaling.enabled` the MachineDeployment gets the Cluster Autoscaler
(`clusterapi` provider) min/max annotations and `replicas` is left out, so Helm does not
fight the autoscaler.

## Rolling changes

`ProxmoxMachineTemplate` and `TalosConfigTemplate` names carry a hash of their spec.
Changing a machine shape or a worker patch creates a new template and CAPI rolls the
affected machines.

Renaming `cluster.name` (or the release, when `cluster.name` is empty) creates a
**new cluster** and deletes the old one. Set `cluster.name` explicitly.
