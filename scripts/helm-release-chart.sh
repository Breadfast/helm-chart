#!/usr/bin/env bash

set -e

function release-helm-chart {
  if [ -n "$(git status --porcelain)" ]; then
    echo -e "\nGit working tree not clean, aborting."
    exit 1
  fi
  echo -e "\nGenerating Helm Chart package for new version."
  changedDir=`git diff --name-only HEAD~1 | awk -F "/*[^/]*/*$" '{ print ($1 == " " ? "." : $1); }' | sort | uniq | head -n1`
  echo "Packaging $changedDir..."
  rm -rf $changedDir/charts/*.tgz
  helm package -u $changedDir

  echo -e "\nSwitching git branch to gh-pages so that we can commit package along the previous versions."
  (git checkout gh-pages \
    && helm repo index . \
    && echo -e "\nCommit new package and index." \
    && git add -A "./*.tgz" ./index.yaml \
    && git commit -m "Update Helm repository from CI." \
    && echo -e "\nGenerating new Helm index, containing all existing versions in gh-pages (previous ones + new one)." \
    && git push origin gh-pages) || echo -e "\nSilently failed to update the chart"
}

# Execute script.
release-helm-chart