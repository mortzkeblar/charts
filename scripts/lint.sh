#!/usr/bin/env bash
# Lint and render every published chart with each of its CI and example values.
# Usage: scripts/lint.sh [chart...]   (default: every chart listed in charts.txt)
set -euo pipefail
cd "$(dirname "$0")/.."

charts=("$@")
[ ${#charts[@]} -gt 0 ] || mapfile -t charts < <(grep -v '^#' charts.txt)

for chart in "${charts[@]}"; do
  echo "::group::${chart}"
  # Register the HTTP repositories the chart depends on, then fetch them
  i=0
  for repo in $(awk '$1 == "repository:" && $2 ~ /^https?:/ {print $2}' "$chart/Chart.yaml"); do
    helm repo add "${chart}-dep-$((i++))" "$repo" --force-update >/dev/null
  done
  helm dependency build "$chart" >/dev/null
  values=$(find "$chart/ci" "$chart/examples" -name '*.yaml' 2>/dev/null | sort || true)
  [ -n "$values" ] || { echo "no ci/ or examples/ values in $chart" >&2; exit 1; }
  for v in $values; do
    echo "--> $v"
    helm lint --strict "$chart" -f "$v"
    helm template ci "$chart" -f "$v" >/dev/null
  done
  echo "::endgroup::"
done
