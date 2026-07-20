{{/*
Expand the name of the chart.
*/}}
{{- define "service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "service.labels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
meta.helm.sh/release-name: {{ .Release.Name }}
meta.helm.sh/release-namespace: {{ .Release.Namespace }}
{{- end }}

{{/*
datadog labels
*/}}
{{- define "datadog.labels" -}}
{{- if .Values.datadog.enabled -}}
tags.datadoghq.com/env: {{ .Release.Namespace }}
tags.datadoghq.com/service: {{ include "service.name" . }}
tags.datadoghq.com/version: {{ (split "_" .Values.image.tag)._2 }}
{{- end -}}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
{{- end }}

{{/*
Comma-separated list of HTTPRoute names this chart renders (see templates/httproute.yaml).
MUST stay in sync with the naming + chunking in httproute.yaml: one HTTPRoute sequence per host,
chunked at gateway.maxRulesPerRoute (default 16), named "<fullname>-httproute-<hostIdx>-<chunkIdx>".
Used by the Rollout gatewayAPI trafficRouting plugin block to reference every route it must manage.
*/}}
{{- define "service.httpRouteNames" -}}
{{- $fullName := include "service.fullname" . -}}
{{- $names := list -}}
{{- $useGatewayBlock := and .Values.gateway.enabled .Values.gateway.hosts -}}
{{- $useIngressGateway := and .Values.ingress.enabled (eq (.Values.ingress.type | default "") "gateway") .Values.ingress.hosts -}}
{{- $counts := list -}}
{{- $maxRules := 16 -}}
{{- if $useGatewayBlock -}}
  {{- $maxRules = int (.Values.gateway.maxRulesPerRoute | default 16) -}}
  {{- $gh := .Values.gateway.hosts -}}
  {{- if and $gh (gt (len $gh) 0) (kindIs "string" (index $gh 0)) -}}
    {{- $n := len (.Values.gateway.paths | default list) -}}
    {{- range $gh -}}{{- $counts = append $counts $n -}}{{- end -}}
  {{- else -}}
    {{- range $gh -}}{{- $counts = append $counts (len (.paths | default list)) -}}{{- end -}}
  {{- end -}}
{{- else if $useIngressGateway -}}
  {{- $maxRules = int (.Values.ingress.gateway.maxRulesPerRoute | default 16) -}}
  {{- range .Values.ingress.hosts -}}{{- $counts = append $counts (len (.paths | default list)) -}}{{- end -}}
{{- end -}}
{{- range $hIdx, $nRules := $counts -}}
  {{- if gt (int $nRules) 0 -}}
    {{- $chunkCount := div (add (int $nRules) (sub $maxRules 1)) $maxRules -}}
    {{- range $cIdx := until (int $chunkCount) -}}
      {{- $names = append $names (printf "%s-httproute-%d-%d" $fullName (int $hIdx) (int $cIdx)) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- join "," $names -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
