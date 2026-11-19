#!/usr/bin/env bash
# Package and push every chart in charts.txt whose version is not published yet.
# Usage: REGISTRY=oci://ghcr.io/<owner>/charts scripts/release.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."

: "${REGISTRY:?set REGISTRY, e.g. oci://ghcr.io/<owner>/charts}"
dry_run=false
[ "${1:-}" = "--dry-run" ] && dry_run=true

mkdir -p .release
mapfile -t charts < <(grep -v '^#' charts.txt)

for chart in "${charts[@]}"; do
  name=$(awk '$1 == "name:" {print $2; exit}' "$chart/Chart.yaml")
  version=$(awk '$1 == "version:" {print $2; exit}' "$chart/Chart.yaml")

  if helm show chart "$REGISTRY/$name" --version "$version" >/dev/null 2>&1; then
    echo "$name $version already published, skipping"
    continue
  fi

  echo "Releasing $name $version"
  i=0
  for repo in $(awk '$1 == "repository:" && $2 ~ /^https?:/ {print $2}' "$chart/Chart.yaml"); do
    helm repo add "${chart}-dep-$((i++))" "$repo" --force-update >/dev/null
  done
  helm dependency build "$chart" >/dev/null
  helm package "$chart" --destination .release >/dev/null

  if $dry_run; then
    echo "  (dry run) would push .release/$name-$version.tgz to $REGISTRY"
    continue
  fi
  helm push ".release/$name-$version.tgz" "$REGISTRY"
done
