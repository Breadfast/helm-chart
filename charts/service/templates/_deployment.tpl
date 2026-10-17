{{/*
One Deployment. Called from deployment.yaml with
  (dict "root" <chart context> "role" "default" | "stable" | "burst")

  default - stableBurst disabled; renders exactly what the chart rendered before stableBurst existed.
  stable  - stableBurst enabled: the baseline Deployment, fixed replicas, high priority, prefers (or requires) on-demand nodes.
  burst   - stableBurst enabled: the autoscaled overflow Deployment, spot nodes only, strict node spread.
*/}}
{{- define "service.deployment" -}}
{{- $root := .root -}}
{{- $role := .role -}}
{{- $values := $root.Values -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ if eq $role "burst" }}{{ include "service.burstName" $root }}{{ else }}{{ include "service.fullname" $root }}{{ end }}
  labels:
  {{- include "service.labels" $root | nindent 4 }}
  {{- if eq $role "burst" }}
    app.kubernetes.io/component: burst
  {{- end }}
  {{- if $values.datadog.enabled }}
    {{- include "datadog.labels" $root | nindent 4 }}
  {{- end }}
  {{- with $values.deploymentLabels }}
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if eq $role "stable" }}
  replicas: {{ include "service.stableReplicas" $root }}
  {{- else if and (eq $role "default") (not (or $values.autoscaling.enabled $values.keda.enabled)) }}
  replicas: {{ $values.replicaCount }}
  {{- end }}
  strategy:
  {{- if $values.rollingStrategy}}
    type: {{ $values.rollingStrategy}}
  {{- else }}
    type: RollingUpdate
  {{- end }}
  selector:
    matchLabels:
      {{- include "service.selectorLabels" $root | nindent 6 }}
      {{- if eq $role "burst" }}
      app.kubernetes.io/component: burst
      {{- end }}
  template:
    metadata:
      annotations:
      {{- with $values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if $values.vaultAgent.enabled }}
        {{- toYaml $values.vaultAgent.annotations | nindent 8 }}
      {{- end }}
      # Enable GCS Fuse volumes if either goreplay or GCP volume mounts are enabled
      {{- if or $values.goreplay.enabled $values.gcpVolumeMounts.enabled }}
        gke-gcsfuse/volumes: "true"
      {{- end }}
      labels:
        {{- include "service.selectorLabels" $root | nindent 8 }}
        {{- if eq $role "burst" }}
        app.kubernetes.io/component: burst
        {{- end }}
        {{- if $values.datadog.enabled }}
          {{- include "datadog.labels" $root | nindent 8 }}
        {{- end }}
        {{- with $values.podLabels }}
          {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      affinity:
        {{- with $values.podAffinity }}
        podAffinity:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with $values.podAntiAffinity }}
        podAntiAffinity:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- if eq $role "stable" }}
        nodeAffinity:
          {{- if eq $values.stableBurst.onDemand "required" }}
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: cloud.google.com/gke-provisioning
                    operator: In
                    values: ["standard"]
          {{- else }}
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: cloud.google.com/gke-provisioning
                    operator: In
                    values: ["standard"]
          {{- end }}
        {{- end }}
      {{- if eq $role "burst" }}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          nodeAffinityPolicy: Honor
          nodeTaintsPolicy: Honor
          labelSelector:
            matchLabels:
              {{- include "service.selectorLabels" $root | nindent 14 }}
              app.kubernetes.io/component: burst
      {{- else }}
      {{- with $values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      {{- if eq $role "burst" }}
      nodeSelector:
        {{- with $values.nodeSelectorLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        cloud.google.com/gke-spot: "true"
      {{- else }}
      {{- with $values.nodeSelectorLabels }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      {{- if eq $role "stable" }}
      priorityClassName: {{ $values.stableBurst.priorityClassName }}
      {{- else }}
      {{- with $values.priorityClassName }}
      priorityClassName: {{ . }}
      {{- end }}
      {{- end }}
      {{- with $values.hostAliases }}
      hostAliases:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if $values.vaultAgent.enabled }}
      serviceAccountName: {{ $values.vaultAgent.serviceAccount }}
      {{- else }}
      serviceAccountName: {{ include "service.serviceAccountName" $root }}
      {{- end }}
      securityContext:
        {{- toYaml $values.podSecurityContext | nindent 8 }}
      {{- if $values.gracePeriod }}
      terminationGracePeriodSeconds: {{ $values.gracePeriod }}
      {{- end }}
      volumes:
      {{- if $values.volumes }}
        {{- toYaml $values.volumes | nindent 8}}
      {{- end }}
      {{- if $values.goreplay.enabled }}
        - name: goreplay-traffic
          csi:
            driver: gcsfuse.csi.storage.gke.io
            volumeAttributes:
              bucketName: {{ $values.goreplay.gcpbucketName }}
              mountOptions: "implicit-dirs"
              gcsfuseLoggingSeverity: warning
      {{- end }}
      tolerations:
      {{- if $values.nodeTolerations }}
        {{- toYaml $values.nodeTolerations | nindent 8}}
      {{- end }}
      {{- if $values.initContainers }}
      initContainers:
        {{- toYaml $values.initContainers | nindent 6}}
      {{- end }}
      containers:
      {{- if $values.goreplay.enabled }}
      - name: goreplay
        image: {{ $values.goreplay.image }}
        command: ["./gor"]
        args: {{ toYaml $values.goreplay.args | nindent 12 }}
        volumeMounts:
        - name: goreplay-traffic
          mountPath: /traffic
      {{- end }}
      - name: {{ include "service.name" $root }}
        securityContext:
          {{- toYaml $values.securityContext | nindent 12 }}
        image: "{{ $values.image.repository }}:{{ $values.image.tag | default $root.Chart.AppVersion }}"
        imagePullPolicy: {{ $values.image.pullPolicy }}
        resources:
          {{- toYaml $values.resources | nindent 12 }}
        {{- if $values.containerLifecycle }}
          {{- toYaml $values.containerLifecycle | nindent 8}}
        {{- end }}
        ports:
          {{- if $values.service.ports }}
          {{- range $values.service.ports }}
          - containerPort: {{ .port }}
            protocol: TCP
          {{- end }}
          {{- else }}
          - containerPort: {{ $values.service.port }}
            protocol: TCP
          {{- end }}
        livenessProbe:
        {{- with $values.livenessProbe }}
          {{- toYaml . | nindent 12 }}
        {{- end }}
        readinessProbe:
        {{- with $values.readinessProbe }}
          {{- toYaml . | nindent 12 }}
        {{- end }}
        startupProbe:
        {{- with $values.startupProbe }}
          {{- toYaml . | nindent 12 }}
        {{- end }}
        env:
        {{- if $values.containerEnv }}
{{ (tpl ( toYaml $values.containerEnv) $root) | indent 12 }}
        {{- end }}
        volumeMounts:
        {{- if $values.volumeMounts }}
          {{- toYaml $values.volumeMounts | nindent 12}}
        {{- end }}
      {{- if $values.sidecars }}
        {{- toYaml $values.sidecars | nindent 6}}
      {{- end }}
---
{{- end }}
