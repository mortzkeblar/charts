{{/*
Altered from techpipe-io/searxng-helm-chart: removed the inline Valkey helpers
(searxng.valkey.fullname, searxng.valkey.authSecretName,
searxng.valkeyPasswordValue, searxng.managedValkeyUrl), added searxng.image,
searxng.valkeyUrl, searxng.secretGuard, and updated
searxng.createRuntimeEnvSecret for the externalValkey.* values.
*/}}
{{- define "searxng.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "searxng.fullname" -}}
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

{{- define "searxng.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "searxng.selectorLabels" -}}
app.kubernetes.io/name: {{ include "searxng.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "searxng.labels" -}}
helm.sh/chart: {{ include "searxng.chart" . }}
{{ include "searxng.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "searxng.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "searxng.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "searxng.runtimeEnvSecretName" -}}
{{- printf "%s-runtime" (include "searxng.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "searxng.configConfigMapName" -}}
{{- printf "%s-config" (include "searxng.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "searxng.configSecretName" -}}
{{- printf "%s-config-secret" (include "searxng.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "searxng.caConfigMapName" -}}
{{- printf "%s-ca" (include "searxng.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "searxng.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "searxng.searxngSecretValue" -}}
{{- if .Values.secret.value -}}
{{- .Values.secret.value -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "searxng.runtimeEnvSecretName" .) -}}
{{- if and $existing (hasKey $existing.data "SEARXNG_SECRET") -}}
{{- index $existing.data "SEARXNG_SECRET" | b64dec -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Refuses to render if SEARXNG_SECRET has no deterministic source: with
secret.create=false (the default) and neither secret.existingSecret nor
secret.value set (and no direct env.values/env.secretValues override), there
is no way to produce SEARXNG_SECRET without falling back to a random value on
every render - which is exactly what this chart is no longer willing to do
silently.
*/}}
{{- define "searxng.secretGuard" -}}
{{- if and (not .Values.secret.create) (not .Values.secret.existingSecret) (not .Values.secret.value) (not (hasKey .Values.env.values "SEARXNG_SECRET")) (not (hasKey .Values.env.secretValues "SEARXNG_SECRET")) -}}
{{- fail "SEARXNG_SECRET is not configured. Set exactly one of: secret.existingSecret (bring your own Secret), secret.value (literal, deterministic), or secret.create=true (chart-generated, non-deterministic - not safe for GitOps, see values.yaml)." -}}
{{- end -}}
{{- end -}}

{{/*
Builds SEARXNG_VALKEY_URL with this precedence:
  1. externalValkey.urlSecret.name set -> empty (Deployment wires a secretKeyRef instead).
  2. externalValkey.url set -> that literal (including whatever DB index is in it).
  3. valkey.enabled -> valkey://[default:<password>@]<host>:<port>/0, where
     <host> mirrors the valkey subchart's own fullname logic (its "valkey.fullname"
     named template can't be `include`d from this chart's context, since it would
     resolve .Values.fullnameOverride/.Values.nameOverride from the wrong dot) and
     the optional credentials come from valkey.auth.aclUsers.default (the only ACL
     user this chart wires into the URL). Always DB 0: this is a fresh bundled
     instance, there's no other DB to pick.
  4. otherwise -> empty (no SEARXNG_VALKEY_URL is set at all).
*/}}
{{- define "searxng.valkeyUrl" -}}
{{- if .Values.externalValkey.urlSecret.name -}}
{{- else if .Values.externalValkey.url -}}
{{- .Values.externalValkey.url -}}
{{- else if .Values.valkey.enabled -}}
{{- $host := .Values.valkey.fullnameOverride -}}
{{- if not $host -}}
{{- $name := default "valkey" .Values.valkey.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- $host = .Release.Name -}}
{{- else -}}
{{- $host = printf "%s-%s" .Release.Name $name -}}
{{- end -}}
{{- end -}}
{{- $host = $host | trunc 63 | trimSuffix "-" -}}
{{- $auth := "" -}}
{{- if .Values.valkey.auth.enabled -}}
{{- $password := dig "default" "password" "" .Values.valkey.auth.aclUsers -}}
{{- if $password -}}
{{- $auth = printf "default:%s@" $password -}}
{{- end -}}
{{- end -}}
{{- printf "valkey://%s%s:%v/0" $auth $host .Values.valkey.service.port -}}
{{- end -}}
{{- end -}}

{{/*
Builds the list of plain env entries for the `searxng` container (as a Go
list of maps, not raw YAML text) so the Deployment can render `env:` only
when the list is non-empty -- otherwise `env:` would be emitted with nothing
under it, i.e. `env: null`, which some strict validators reject since
corev1.Container.env is a list, not a nullable scalar.
*/}}
{{- define "searxng.envEntries" -}}
{{- $entries := list -}}
{{- if and .Values.secret.existingSecret (not (hasKey .Values.env.values "SEARXNG_SECRET")) (not (hasKey .Values.env.secretValues "SEARXNG_SECRET")) -}}
{{- $entries = append $entries (dict "name" "SEARXNG_SECRET" "valueFrom" (dict "secretKeyRef" (dict "name" .Values.secret.existingSecret "key" .Values.secret.existingSecretKey))) -}}
{{- end -}}
{{- if and .Values.externalValkey.urlSecret.name (not (hasKey .Values.env.values "SEARXNG_VALKEY_URL")) (not (hasKey .Values.env.secretValues "SEARXNG_VALKEY_URL")) -}}
{{- $entries = append $entries (dict "name" "SEARXNG_VALKEY_URL" "valueFrom" (dict "secretKeyRef" (dict "name" .Values.externalValkey.urlSecret.name "key" .Values.externalValkey.urlSecret.key))) -}}
{{- end -}}
{{- range $k, $v := .Values.env.values -}}
{{- $entries = append $entries (dict "name" $k "value" (toString $v)) -}}
{{- end -}}
{{- if $entries -}}
{{- $entries | toYaml -}}
{{- end -}}
{{- end -}}

{{- define "searxng.createRuntimeEnvSecret" -}}
{{- if or (and (or .Values.secret.create .Values.secret.value) (not .Values.secret.existingSecret) (not (hasKey .Values.env.values "SEARXNG_SECRET")) (not (hasKey .Values.env.secretValues "SEARXNG_SECRET"))) (gt (len .Values.env.secretValues) 0) (and (not (hasKey .Values.env.values "SEARXNG_VALKEY_URL")) (not (hasKey .Values.env.secretValues "SEARXNG_VALKEY_URL")) (not .Values.externalValkey.urlSecret.name) (or .Values.externalValkey.url .Values.valkey.enabled)) -}}true{{- end -}}
{{- end -}}
