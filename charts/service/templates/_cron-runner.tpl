{{/* Name shared by the cron-runner ConfigMap, Deployment and pod label. Must never equal
service.name: the Service, HPA and PDB select on app.kubernetes.io/name (see cronjob.yaml). */}}
{{- define "service.cronRunnerName" -}}
{{- printf "%s-cron-runner" (include "service.fullname" . | trunc 51 | trimSuffix "-") -}}
{{- end -}}

{{/* Renders nothing; fails the render on an invalid cronRunner block. */}}
{{- define "service.cronRunnerValidate" -}}
{{- $cr := .Values.cronRunner -}}
{{- if not $cr.image.repository }}{{ fail "cronRunner.image.repository is required" }}{{ end -}}
{{- if not $cr.image.tag }}{{ fail "cronRunner.image.tag is required" }}{{ end -}}
{{- if not $cr.target }}{{ fail "cronRunner.target is required" }}{{ end -}}
{{- if not $cr.host }}{{ fail "cronRunner.host is required" }}{{ end -}}
{{- $hasToken := false -}}
{{- range $cr.crons }}{{ if .token }}{{ $hasToken = true }}{{ end }}{{ end -}}
{{- if $hasToken -}}
{{- if not $cr.vault.role }}{{ fail "cronRunner.vault.role is required when a cron uses a token" }}{{ end -}}
{{- if not $cr.serviceAccount }}{{ fail "cronRunner.serviceAccount is required when a cron uses a token" }}{{ end -}}
{{- end -}}
{{- $seen := dict -}}
{{- range $i, $c := $cr.crons -}}
{{- $n := toString $c.name -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $n) }}{{ fail (printf "cronRunner.crons[%d].name %q must be lowercase letters, digits and dashes" $i $n) }}{{ end -}}
{{- if hasKey $seen $n }}{{ fail (printf "cronRunner.crons: duplicate name %q" $n) }}{{ end -}}
{{- $_ := set $seen $n true -}}
{{- if not (regexMatch "^[^ ]+( [^ ]+){4}$" (toString $c.schedule)) }}{{ fail (printf "cronRunner.crons %s: schedule must have 5 fields" $n) }}{{ end -}}
{{- if not (regexMatch "^/[^'\"\\\\\\s]*$" (toString $c.path)) }}{{ fail (printf "cronRunner.crons %s: path must start with / and contain no quote, backslash or space" $n) }}{{ end -}}
{{- if not (has (upper (toString (default "GET" $c.method))) (list "GET" "POST" "PUT" "DELETE")) }}{{ fail (printf "cronRunner.crons %s: method must be GET, POST, PUT or DELETE" $n) }}{{ end -}}
{{- if $c.token -}}
{{- if not (regexMatch "^[A-Z][A-Z0-9_]*$" (toString $c.token)) }}{{ fail (printf "cronRunner.crons %s: token must be an upper-case Vault key" $n) }}{{ end -}}
{{- if not $cr.vault.path }}{{ fail (printf "cronRunner.crons %s: token needs cronRunner.vault.path" $n) }}{{ end -}}
{{- end -}}
{{- if hasKey $c "timeout" }}{{ if lt (int $c.timeout) 1 }}{{ fail (printf "cronRunner.crons %s: timeout must be a positive number of seconds" $n) }}{{ end }}{{ end -}}
{{- end -}}
{{- end -}}

{{/* Sorted unique token keys of ALL crons (enabled or not), comma-joined. */}}
{{- define "service.cronRunnerTokens" -}}
{{- $keys := list -}}
{{- range .Values.cronRunner.crons }}{{ if .token }}{{ $keys = append $keys (toString .token) }}{{ end }}{{ end -}}
{{- $keys | uniq | sortAlpha | join "," -}}
{{- end -}}

{{/* Largest timeout across the default and all crons. */}}
{{- define "service.cronRunnerMaxTimeout" -}}
{{- $max := int .Values.cronRunner.timeout -}}
{{- range .Values.cronRunner.crons }}{{ if hasKey . "timeout" }}{{ $max = max $max (int .timeout) }}{{ end }}{{ end -}}
{{- $max -}}
{{- end -}}
