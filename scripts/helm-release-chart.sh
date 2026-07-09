#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://breadfast.github.io/helm-chart"

# Packages the charts under charts/* and publishes the .tgz + a merged
# index.yaml to the gh-pages branch (the Breadfast public Helm registry).
# Previously this only handled charts/service; it now loops over all charts so
# new charts (e.g. charts/rudderstack) are published without further edits.
#
# GUARD: --merge would silently overwrite a published version in place. So:
#   - if a chart CHANGED in this commit but its version is already published,
#     FAIL (someone forgot to bump the version);
#   - if a chart's version is already published and it did NOT change, SKIP it
#     (leave the published artifact untouched);
#   - otherwise package it (new/bumped version).
function release-helm-charts {
  git fetch origin gh-pages --depth=1 || true

  local changedFiles
  changedFiles="$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"

  echo -e "\nSelecting charts to package ..."
  local toPackage=()
  for chartDir in charts/*/; do
    [ -f "${chartDir}Chart.yaml" ] || continue
    local name version
    name="$(awk '/^name:/{print $2; exit}' "${chartDir}Chart.yaml")"
    version="$(awk '/^version:/{print $2; exit}' "${chartDir}Chart.yaml")"

    if git cat-file -e "origin/gh-pages:${name}-${version}.tgz" 2>/dev/null; then
      if echo "${changedFiles}" | grep -q "^${chartDir}"; then
        echo "ERROR: ${chartDir} changed but ${name}-${version} is already published." >&2
        echo "Bump the version in ${chartDir}Chart.yaml before merging." >&2
        exit 1
      fi
      echo "Skipping ${name}-${version} (already published, unchanged)."
      continue
    fi
    toPackage+=("${chartDir}")
  done

  if [ "${#toPackage[@]}" -eq 0 ]; then
    echo "No new chart versions to publish."; return 0
  fi

  echo -e "\nPackaging: ${toPackage[*]}"
  for chartDir in "${toPackage[@]}"; do
    rm -rf "${chartDir}charts/"*.tgz 2>/dev/null || true
    helm dependency update "${chartDir}" || true
    helm package "${chartDir}"
  done

  echo -e "\nSwitching to gh-pages to commit packages alongside previous versions."
  git checkout gh-pages
  # Absolute URLs for new entries (--url); --merge preserves existing entries.
  helm repo index . --merge index.yaml --url "${REPO_URL}"
  git add -A "./*.tgz" ./index.yaml
  git commit -m "Update Helm repository from CI."
  git push origin gh-pages
}

# Execute Helm Release script.
release-helm-charts
