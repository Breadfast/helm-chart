{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "rudderstack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rudderstack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rudderstack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "rudderstack.labels" -}}
helm.sh/chart: {{ include "rudderstack.chart" . }}
{{ include "rudderstack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.commonLabels}}
{{ toYaml .Values.commonLabels }}
{{- end }}
{{- end -}}

{{/*
Selector labels (chart-wide)
*/}}
{{- define "rudderstack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rudderstack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Per-role selector labels. The component label keeps the gateway and processor
selectors (which are immutable) distinct while sharing the chart-wide labels.
*/}}
{{- define "gateway.selectorLabels" -}}
{{ include "rudderstack.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end -}}

{{- define "processor.selectorLabels" -}}
{{ include "rudderstack.selectorLabels" . }}
app.kubernetes.io/component: processor
{{- end -}}

{{- define "gateway.fullname" -}}
{{- printf "%s-gateway" (include "rudderstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "processor.fullname" -}}
{{- printf "%s-processor" (include "rudderstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "metricsAggregator.fullname" -}}
{{- printf "%s-metrics-aggregator" (include "rudderstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "metricsAggregator.selectorLabels" -}}
{{ include "rudderstack.selectorLabels" . }}
app.kubernetes.io/component: metrics-aggregator
{{- end -}}

{{/*
Workspace-token Secret name (AVP-backed unless an existing secret is provided).
*/}}
{{- define "rudderstack.rudderWorkspaceTokenSecretName" -}}
{{- default (include "rudderstack.fullname" .) .Values.rudderWorkspaceTokenExistingSecret -}}
{{- end -}}

{{/*
DB credentials Secret name (AVP-backed unless an existing secret is provided).
*/}}
{{- define "rudderstack.dbSecretName" -}}
{{- default (printf "%s-db" (include "rudderstack.fullname" .)) .Values.backend.db.existingSecret -}}
{{- end -}}

{{- define "transformer.name" -}}
{{- printf "%s-%s" (include "rudderstack.name" .) "transformer" -}}
{{- end -}}

{{- define "transformer.fullname" -}}
{{- printf "%s-%s" (include "rudderstack.fullname" .) "transformer" -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for StatefulSet/Deployment.
*/}}
{{- define "statefulset.apiVersion" -}}
{{- if semverCompare "<1.14-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "apps/v1beta2" -}}
{{- else -}}
{{- print "apps/v1" -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "rudderstack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "rudderstack.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
External Cloud SQL JobsDB connection env. The JOBS_DB_* names are the explicit
BindEnv aliases for the DB.* config keys
(rudder-go-kit@v0.75.0/config/config.go:252-257); host/port/name/sslMode come
from values, user/password from the AVP-populated Secret via secretKeyRef.
*/}}
{{- define "rudderstack.dbEnv" -}}
- name: JOBS_DB_HOST
  value: {{ required "backend.db.host (Cloud SQL private IP) is required" .Values.backend.db.host | quote }}
- name: JOBS_DB_PORT
  value: {{ .Values.backend.db.port | quote }}
- name: JOBS_DB_DB_NAME
  value: {{ .Values.backend.db.name | quote }}
- name: JOBS_DB_SSL_MODE
  value: {{ .Values.backend.db.sslMode | quote }}
- name: JOBS_DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "rudderstack.dbSecretName" . }}
      key: {{ .Values.backend.db.userKey }}
- name: JOBS_DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "rudderstack.dbSecretName" . }}
      key: {{ .Values.backend.db.passwordKey }}
{{- end -}}

{{/*
Environment shared by both gateway and processor pods (control plane, transformer
URL, instance identity, GCS backups via backend.extraEnvVars, and the DB env).
APP_TYPE and the processor-only RSERVER_ENABLE_* flags are added per workload.
*/}}
{{- define "rudderstack.sharedEnv" -}}
{{- with .Values.backend.extraEnvVars }}
{{- toYaml . }}
{{- end }}
- name: CONFIG_BACKEND_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "rudderstack.rudderWorkspaceTokenSecretName" . }}
      key: {{ .Values.backend.workspaceTokenKey }}
{{- if .Values.backend.controlPlaneJSON }}
- name: RSERVER_BACKEND_CONFIG_CONFIG_FROM_FILE
  value: "true"
- name: RSERVER_BACKEND_CONFIG_CONFIG_JSONPATH
  value: "{{ .Values.backend.config.mountPath }}/workspaceConfig.json"
{{- end }}
- name: DEST_TRANSFORM_URL
  value: "http://{{ include "transformer.fullname" . }}:{{ .Values.transformer.service.port }}"
- name: INSTANCE_ID
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: KUBE_NAMESPACE
  value: {{ .Release.Namespace }}
{{- with .Values.backend.gcs.workloadIdentityType }}
# Keyless GCS auth: workloadIdentity.type=GKE makes rudder-server skip key-based
# credentials and use ADC (the pod's KSA -> GSA). Requires GOOGLE_APPLICATION_
# CREDENTIALS to stay UNSET (we do not set it) so ADC resolves via the GKE
# metadata server. (googleutil.go:59-62, gcsmanager.go:184-199 @ v1.74.1)
- name: RSERVER_WORKLOAD_IDENTITY_TYPE
  value: {{ . | quote }}
{{- end }}
{{ include "rudderstack.dbEnv" . }}
{{- end -}}

{{/*
Anti-spot node affinity (keep ingestion/processing off preemptible nodes),
merged with any user-supplied affinity.
*/}}
{{- define "rudderstack.antiSpotNodeAffinity" -}}
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: cloud.google.com/gke-spot
            operator: NotIn
            values:
              - "true"
{{- end -}}

{{/*
Shared volumes for the rudder-server pods. GCS backups use keyless Workload
Identity (ADC via the pod KSA), so no credentials secret is mounted.
*/}}
{{- define "rudderstack.backendVolumes" -}}
- name: backend-config-volume
  configMap:
    defaultMode: 420
    name: {{ include "rudderstack.fullname" . }}-config
{{- end -}}

{{/*
Shared volumeMounts for the rudder-server container (data mount differs per role
and is added by the workload template).
*/}}
{{- define "rudderstack.backendVolumeMounts" -}}
- name: backend-config-volume
  mountPath: {{ .Values.backend.config.mountPath }}
{{- end -}}
