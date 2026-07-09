# rudderstack

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.74.1](https://img.shields.io/badge/AppVersion-1.74.1-informational?style=flat-square)

Breadfast self-hosted RudderStack (Segment-alternative) data plane.

Split topology against an EXTERNAL Cloud SQL (Postgres) JobsDB:
  - transformer : Deployment (>=3 replicas) + ClusterIP Service + PDB (subchart)
  - processor   : StatefulSet replicas=1, APP_TYPE=PROCESSOR (single "brain":
                  processor + router + batch-router + embedded warehouse)
  - gateway     : Deployment (N replicas), APP_TYPE=GATEWAY, behind the ingress

The in-cluster PostgreSQL subchart from the upstream chart is intentionally
removed; JobsDB is an external Cloud SQL instance reached over its private IP.
DB credentials are supplied by Vault via the ArgoCD Vault Plugin (AVP) - the
chart carries placeholders only, never plaintext.

**Homepage:** <https://github.com/Breadfast/helm-chart>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| DevOps-team | <devops@breadfast.com> |  |

## Source Code

* <https://github.com/Breadfast/helm-chart>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://charts/transformer | transformer | 0.1.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| backend.config.mountPath | string | `"/etc/rudderstack"` |  |
| backend.config.overrides | object | `{}` |  |
| backend.controlPlaneJSON | bool | `false` |  |
| backend.db | object | `{"existingSecret":"","host":"","name":"jobsdb","passwordKey":"db_password","port":5432,"sslMode":"require","userKey":"db_user"}` | External Cloud SQL (Postgres) JobsDB. Reached over the PRIVATE IP    directly: no Cloud SQL Auth Proxy sidecar, no IAM DB auth.    host/port/name/sslMode come from here; user/password come from Vault. |
| backend.extraEnvVars | list | `[{"name":"CONFIG_PATH","value":"/etc/rudderstack/config.yaml"},{"name":"RUDDER_TMPDIR","value":"/data/rudderstack"},{"name":"JOBS_BACKUP_STORAGE_PROVIDER","value":"GCS"},{"name":"LOG_LEVEL","value":"INFO"},{"name":"RSERVER_GATEWAY_WEBHOOK_SOURCE_LIST_FOR_PARSING_PARAMS","value":"Shopify"},{"name":"RSERVER_OPEN_TELEMETRY_ENABLED","value":"true"},{"name":"RSERVER_OPEN_TELEMETRY_METRICS_PROMETHEUS_ENABLED","value":"true"},{"name":"RSERVER_OPEN_TELEMETRY_METRICS_PROMETHEUS_PORT","value":"9182"}]` | Environment shared by BOTH gateway and processor pods.    (DB.* env and APP_TYPE are injected by the templates, not here.)    GENERIC defaults only. Helm REPLACES this whole list on override, so the    private overlay must re-supply the full set INCLUDING the internal bits it    adds: CONFIG_BACKEND_URL (control plane), JOBS_BACKUP_BUCKET /    JOB_STATUS_BACKUP_BUCKET (GCS backup buckets), and any BUGSNAG_KEY. |
| backend.gateway | object | `{"affinity":{},"metricsService":{"enabled":false,"name":"rudder-gateway-metrics"},"nodeSelector":{},"pdb":{"enabled":true,"maxUnavailable":1},"podAnnotations":{},"podLabels":{},"replicaCount":2,"resources":{"limits":{"memory":"2048Mi"},"requests":{"cpu":"500m","memory":"1024Mi"}},"service":{"annotations":{},"labels":{},"port":80,"type":"ClusterIP"},"terminationGracePeriodSeconds":60,"tolerations":[],"topologySpreadConstraints":[],"webPort":8080}` | ----------------------------------------------------------------------- |
| backend.gcs | object | `{"workloadIdentityType":"GKE"}` | Keyless GCS auth for JobsDB backups via Workload Identity.    "GKE" => rudder-server sets workloadIdentity.type=GKE and uses ADC (the    pod's KSA -> GSA); no credentials key file. Empty "" disables it (would    require key-based auth, which this chart no longer wires). The KSA must be    annotated with the GSA (serviceAccount.annotations, from the overlay) and    GOOGLE_APPLICATION_CREDENTIALS must stay unset. |
| backend.image.pullPolicy | string | `"IfNotPresent"` |  |
| backend.image.repository | string | `"rudderlabs/rudder-server"` |  |
| backend.image.version | string | `"1.74.1"` |  |
| backend.metricsPort | int | `9182` | Port rudder-server exposes Prometheus metrics on (matches the env above). |
| backend.processor | object | `{"affinity":{},"enableProcessor":true,"enableRouter":true,"metricsService":{"enabled":true,"name":"rudder-metrics"},"nodeSelector":{},"persistence":{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":true,"size":"20Gi"},"podAnnotations":{},"podLabels":{},"resources":{"limits":{"memory":"4096Mi"},"requests":{"cpu":"1","memory":"2048Mi"}},"terminationGracePeriodSeconds":300,"tolerations":[],"topologySpreadConstraints":[],"warehouseMode":"embedded","webPort":8086}` | ----------------------------------------------------------------------- |
| backend.workspaceTokenKey | string | `"workspace_token"` | Vault key (under vault.path) for the workspace token -> CONFIG_BACKEND_TOKEN. |
| commonLabels | object | `{}` | Labels applied to every resource in the chart. |
| global.imagePullSecrets | list | `[]` |  |
| global.storageClass | string | `""` | StorageClass for the processor's RUDDER_TMPDIR PVC ("" = cluster default). |
| ingress.annotations."kubernetes.io/ingress.class" | string | `"nginx"` |  |
| ingress.enabled | bool | `true` |  |
| ingress.hostname | string | `"rudderstack.local"` |  |
| ingress.ingressClassName | string | `"nginx"` |  |
| ingress.labels | object | `{}` |  |
| ingress.secretName | string | `""` |  |
| ingress.tls | bool | `true` |  |
| persistence | object | `{"mountPath":"/data/rudderstack"}` | Persistent mount path inside both pods for RUDDER_TMPDIR / recovery files. |
| priorityClass.create | bool | `true` |  |
| priorityClass.description | string | `"Breadfast RudderStack ingestion/processing - keep off the eviction list."` |  |
| priorityClass.name | string | `"rudderstack-critical"` |  |
| priorityClass.value | int | `1000000000` |  |
| rudderWorkspaceTokenExistingSecret | string | `""` | Optional override for the workspace-token Secret (CONFIG_BACKEND_TOKEN).    Leave empty to let the chart render its own AVP-backed Secret. |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| syncWaves | object | `{"gateway":"2","prereqs":"-1","processor":"1","transformer":"0"}` | ------------------------------------------------------------------------- |
| transformer.affinity | object | `{}` |  |
| transformer.extraEnvVars | list | `[]` |  |
| transformer.image.pullPolicy | string | `"IfNotPresent"` |  |
| transformer.image.repository | string | `"rudderstack/rudder-transformer"` |  |
| transformer.image.version | string | `"1.74.1"` |  |
| transformer.metricsService.enabled | bool | `false` |  |
| transformer.metricsService.name | string | `"rudder-transformer-metrics"` |  |
| transformer.metricsService.port | int | `9182` |  |
| transformer.nodeSelector | object | `{}` |  |
| transformer.pdb.enabled | bool | `true` |  |
| transformer.pdb.minAvailable | int | `2` |  |
| transformer.priorityClassName | string | `"rudderstack-critical"` |  |
| transformer.replicaCount | int | `3` |  |
| transformer.resources.limits.cpu | string | `"1500m"` |  |
| transformer.resources.limits.memory | string | `"2048Mi"` |  |
| transformer.resources.requests.cpu | string | `"500m"` |  |
| transformer.resources.requests.memory | string | `"512Mi"` |  |
| transformer.service.port | int | `9090` |  |
| transformer.service.type | string | `"ClusterIP"` |  |
| transformer.syncWave | string | `"0"` |  |
| transformer.tolerations | list | `[]` |  |
| transformer.topologySpreadConstraints | list | `[]` |  |
| vault | object | `{"path":""}` | ------------------------------------------------------------------------- All secret material is resolved at ArgoCD sync time from Vault. The chart only ever renders "<path:...#key>" PLACEHOLDERS - never plaintext. The concrete Vault path is INTERNAL and MUST be supplied by the private overlay; left empty here so nothing internal ships in the public chart. The secret templates only render when vault.path is set. |
| vault.path | string | `""` | Vault KV-v2 path holding this app's secrets (no trailing slash).    Set in the private overlay, e.g. "devops/data/argocd/rudderstack/<env>". |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
