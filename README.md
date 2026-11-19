# charts

Helm charts I use in my homelab.

| Chart | Description |
|---|---|
| [proxmox-talos-cluster](proxmox-talos-cluster) | Talos Linux cluster on Proxmox VE, managed by Cluster API |
| [searxng](searxng) | SearXNG metasearch engine, with optional Valkey |

`memos/` is a work in progress and is not published yet.

## Usage

Charts are published as OCI artifacts to GitHub Container Registry:

```bash
helm install <release> oci://ghcr.io/mortzkeblar/charts/<chart> --version <version>
```

Each chart's README documents its values.

## Development

```bash
scripts/lint.sh            # lint and render every chart with its ci/ and examples/ values
```

A chart is released by bumping `version` in its `Chart.yaml`: on every push to
`main`, CI publishes the charts listed in [charts.txt](charts.txt) whose version is
not in the registry yet.

## License

[Apache License 2.0](LICENSE). searxng is a derivative of
[techpipe-io/searxng-helm-chart](https://github.com/techpipe-io/searxng-helm-chart),
see its [NOTICE](searxng/NOTICE).
