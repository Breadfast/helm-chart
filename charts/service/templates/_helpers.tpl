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
Autoscaler scaling behavior, shared by the HPA (templates/hpa.yaml) and the KEDA
ScaledObject (templates/keda-scaledobject.yaml) so the two cannot drift: a service
that flips keda.enabled keeps the scaling dynamics it had under the HPA.

Call with a dict of the two knobs from the RELEVANT values block - autoscaling.* for
the HPA, keda.* for the ScaledObject - so neither block silently tunes the other:
  (dict "scaledownStabilization" .Values.autoscaling.scaledownStabilization
        "podsIncrease"           .Values.autoscaling.podsIncrease)

Renders the bare HorizontalPodAutoscalerBehavior body; the caller supplies the
`behavior:` key and the indentation. KEDA's advanced.horizontalPodAutoscalerConfig
.behavior takes the same schema as autoscaling/v2, so one definition serves both.
*/}}
{{- define "service.autoscalingBehavior" -}}
scaleDown:
{{- if .scaledownStabilization }}
  stabilizationWindowSeconds: {{ .scaledownStabilization }}
{{- end }}
  policies:
    - type: Pods
      value: 1
      periodSeconds: 120
scaleUp:
  stabilizationWindowSeconds: 0
{{- if .podsIncrease }}
  policies:
  - type: Pods
    value: {{ .podsIncrease }}
    periodSeconds: 60
{{- else }}
  policies:
  - type: Pods
    value: 2
    periodSeconds: 60
  - type: Percent
    value: 10
    periodSeconds: 60
{{- end }}
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

{{/*
Name of the burst Deployment. The stable Deployment keeps service.fullname so enabling
stableBurst does not delete and recreate it. Truncated so the suffix still fits in 63 chars.
*/}}
{{- define "service.burstName" -}}
{{- printf "%s-burst" (include "service.fullname" . | trunc 56 | trimSuffix "-") }}
{{- end }}

{{/*
Number of baseline (stable) replicas: stableBurst.stableReplicas, else the autoscaler's
minimum (keda.minReplicaCount or autoscaling.minReplicas).
*/}}
{{- define "service.stableReplicas" -}}
{{- if .Values.stableBurst.stableReplicas -}}
{{- .Values.stableBurst.stableReplicas -}}
{{- else if .Values.keda.enabled -}}
{{- .Values.keda.minReplicaCount | default 0 -}}
{{- else -}}
{{- .Values.autoscaling.minReplicas | default 0 -}}
{{- end -}}
{{- end }}

{{/*
Burst Deployment's maximum replicas: stableBurst.burst.maxReplicas, else the autoscaler's
maximum minus the stable replicas. Empty when KEDA has no maxReplicaCount (KEDA's own default applies).
*/}}
{{- define "service.burstMaxReplicas" -}}
{{- if .Values.stableBurst.burst.maxReplicas -}}
{{- .Values.stableBurst.burst.maxReplicas -}}
{{- else if .Values.keda.enabled -}}
{{- if hasKey .Values.keda "maxReplicaCount" -}}
{{- sub (int .Values.keda.maxReplicaCount) (int (include "service.stableReplicas" .)) -}}
{{- end -}}
{{- else -}}
{{- sub (int .Values.autoscaling.maxReplicas) (int (include "service.stableReplicas" .)) -}}
{{- end -}}
{{- end }}

{{/*
Render-time validation for stableBurst. Included from deployment.yaml, which renders
whether or not Argo Rollouts is enabled, so every misconfiguration fails the render.
*/}}
{{- define "service.stableBurstValidate" -}}
{{- if .Values.stableBurst.enabled -}}
{{- if .Values.argorollouts.enabled -}}
{{- fail "stableBurst.enabled is not supported together with argorollouts.enabled." -}}
{{- end -}}
{{- if not .Values.stableBurst.priorityClassName -}}
{{- fail "stableBurst.enabled requires stableBurst.priorityClassName (prod-baseline-critical or prod-baseline). A name that does not exist makes every pod fail admission while ArgoCD still reports Synced." -}}
{{- end -}}
{{- if not (has .Values.stableBurst.onDemand (list "preferred" "required")) -}}
{{- fail "stableBurst.onDemand must be \"preferred\" or \"required\"." -}}
{{- end -}}
{{- if not (or .Values.autoscaling.enabled .Values.keda.enabled) -}}
{{- fail "stableBurst.enabled requires autoscaling.enabled or keda.enabled: the burst Deployment is sized by the autoscaler." -}}
{{- end -}}
{{- $stable := int (include "service.stableReplicas" .) -}}
{{- if lt $stable 1 -}}
{{- fail "stableBurst needs at least 1 stable replica: set stableBurst.stableReplicas, autoscaling.minReplicas or keda.minReplicaCount." -}}
{{- end -}}
{{- $burstMax := include "service.burstMaxReplicas" . -}}
{{- if and $burstMax (lt (int $burstMax) 1) -}}
{{- fail (printf "stableBurst leaves no room for burst: stable replicas (%d) must be below the autoscaler maximum." $stable) -}}
{{- end -}}
{{- if and (not .Values.keda.enabled) (lt (int .Values.stableBurst.burst.minReplicas) 1) -}}
{{- fail "stableBurst.burst.minReplicas must be >= 1 with the HPA; only KEDA can scale the burst Deployment to 0." -}}
{{- end -}}
{{- end -}}
{{- end }}
