# helm-chart

A Helm chart for Kubernetes

![Version: 0.14.7](https://img.shields.io/badge/Version-0.14.7-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

# Breadfast Centralized Helm Repository

The purpose of this repository is to provide a place for maintaining and contributing Breadfast Charts, with CI processes in place for managing the releasing of Charts into the repository and having a unified Configuration Management

Helm chart is maintained by the DevOps team and which conform to the best practices and standards of our Kubernetes clusters.

# How it works ?

- Add the Helm Charts for your client, you will need a `GITHUB_TOKEN` with `repo` scope:

```bash
helm repo add breadfast $HELM_REPO --username $GITHUB_USER --password $GITHUB_TOKEN
helm dependency update .
```

Syntax testing and Dry run:

```bash
helm template . | kubectl apply --dry-run -f -
```

Packaging and Pushing the helm release tgz file:

```bash
helm package .
helm cm-push ./service-${RELEASE_VERSION}.tgz helm-chart
```