#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://breadfast.github.io/helm-chart"

# Packages the charts under charts/* and publishes the .tgz + a merged
# index.yaml to the gh-pages branch (the Breadfast public Helm registry).
# Loops over all charts so new charts (e.g. charts/rudderstack) publish without
# further edits.
#
# GUARD (prevents --merge from silently overwriting a published version):
#   - chart CHANGED in this commit but its version is already published -> FAIL;
#   - version already published and unchanged -> SKIP;
#   - otherwise package it (new/bumped version).
#
# Publishing happens in a SEPARATE git worktree for gh-pages so the packaging
# artifacts in the main tree (vendored dependency .tgz created by `helm
# dependency update`, Chart.lock touch-ups) never collide with a branch switch.
function release-helm-charts {
  git fetch origin gh-pages --depth=1 || true

  local changedFiles
  changedFiles="$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"

  local pkgDir
  pkgDir="$(mktemp -d)"

  echo -e "\nSelecting charts to package ..."
  local packaged=0
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

    echo "Packaging ${name}-${version} ..."
    helm dependency update "${chartDir}" >/dev/null 2>&1 || true
    helm package "${chartDir}" -d "${pkgDir}"   # chart package lands in pkgDir
    packaged=$((packaged + 1))
  done

  if [ "${packaged}" -eq 0 ]; then
    echo "No new chart versions to publish."; rm -rf "${pkgDir}"; return 0
  fi

  echo -e "\nPublishing to gh-pages via a dedicated (detached) worktree ..."
  local ghp
  ghp="$(mktemp -d)"
  git worktree add --force --detach "${ghp}" origin/gh-pages

  (
    cd "${ghp}"
    # gh-pages must only hold index.yaml + top-level <chart>-<ver>.tgz. Remove any
    # stray nested chart dirs accidentally published by an earlier revision.
    if [ -d charts ]; then git rm -r -q --ignore-unmatch charts >/dev/null 2>&1 || true; rm -rf charts; fi
    cp "${pkgDir}"/*.tgz .
    helm repo index . --merge index.yaml --url "${REPO_URL}"
    git add ./*.tgz index.yaml
    git commit -m "Update Helm repository from CI."
    git push origin HEAD:gh-pages
  )

  git worktree remove --force "${ghp}" || true
  rm -rf "${pkgDir}"
}

# Execute Helm Release script.
release-helm-charts
