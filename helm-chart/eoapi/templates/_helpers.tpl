{{/*
Expand the name of the chart.
*/}}
{{- define "eoapi.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "eoapi.fullname" -}}
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
{{- define "eoapi.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "eoapi.labels" -}}
helm.sh/chart: {{ include "eoapi.chart" . }}
{{ include "eoapi.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "eoapi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eoapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "eoapi.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "eoapi.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create pgstac host string depending if .Values.testing
*/}}
{{- define "eoapi.pgstacTempDbHostName" -}}
{{- if .Values.testing }}
{{- printf "%s-%s" "pgstac" .Release.Name }}
{{- else }}
{{/* need to match what is default in values.yamls */}}
{{- printf "%s" "pgstac" }}
{{- end }}
{{- end }}

{{/*
Create pgstac host string depending if .Values.testing
*/}}
{{- define "eoapi.pgstacHostName" -}}
{{- if .Values.testing }}
{{- printf "%s-%s" "pgstacbootstrap" .Release.Name }}
{{- else }}
{{/* need to match what is default in values.yamls */}}
{{- printf "%s" "pgstacbootstrap" }}
{{- end }}
{{- end }}

{{/*
Secrets for postgres/postgis access have to be
derived from what the crunchydata operator creates

Also note that we want to use the pgbouncer-<port|host|uri>
but currently it doesn't support `search_path` parameters
(https://github.com/pgbouncer/pgbouncer/pull/73) which
are required for much of *pgstac
*/}}
{{- define "eoapi.pgstacSecrets"  -}}
{{- range $userName, $v := .Values.postgrescluster.users -}}
{{/* do not render anything for the "postgres" user */}}
{{- if not (eq (index $v "name") "postgres") }}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: user
- name: POSTGRES_PORT
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: port
- name: POSTGRES_HOST
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: POSTGRES_HOST_READER
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: POSTGRES_HOST_WRITER
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: POSTGRES_PASS
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: password
- name: POSTGRES_DBNAME
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: dbname
- name: PGBOUNCER_URI
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: pgbouncer-uri
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $.Release.Name }}-pguser-{{ index $v "name" }}
      key: uri
{{- end }}
{{- end }}
- name: PGADMIN_URI
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-pguser-postgres
      key: uri
{{- end }}

{{/*
values.schema.json doesn't play nice combined value checks
so we use this helper function to check autoscaling rules
*/}}
{{- define "eoapi.validateAutoscaleRules" -}}
{{- if and .Values.ingress.enabled (ne .Values.ingress.className "nginx") }}
{{/* "requestRate" cannot be enabled for any service if not "nginx" so give feedback and fail */}}
{{- if (or (and .Values.raster.autoscaling.enabled (eq .Values.raster.autoscaling.type "requestRate")) (and .Values.stac.autoscaling.enabled (eq .Values.stac.autoscaling.type "requestRate")) (and .Values.vector.autoscaling.enabled (eq .Values.vector.autoscaling.type "requestRate")) ) }}
{{- fail "When using an 'ingress.className' other than 'nginx' you cannot enable autoscaling by 'requestRate' at this time b/c it's solely an nginx metric" }}
{{- end }}
{{/* "both" cannot be enabled for any service if not "nginx" so give feedback and fail */}}
{{- if (or (and .Values.raster.autoscaling.enabled (eq .Values.raster.autoscaling.type "both")) (and .Values.stac.autoscaling.enabled (eq .Values.stac.autoscaling.type "both")) (and .Values.vector.autoscaling.enabled (eq .Values.vector.autoscaling.type "both")) ) }}
{{- fail "When using an 'ingress.className' other than 'nginx' you cannot enable autoscaling by 'both' at this time b/c 'requestRate' is solely an nginx metric" }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
validate:
1. the .Values.postgrescluster.users array does not have more than two elements.
2. at least one of the users is named "postgres".
*/}}
{{- define "eoapi.validatePostgresCluster" -}}
{{- $users := .Values.postgrescluster.users | default (list) -}}

{{- if gt (len $users) 2 -}}
  {{- fail "The users array in postgrescluster should not have more than two users declared b/c the last user declared will override all secrets generated in eoapi.pgstacSecrets" -}}
{{- end -}}

{{- $hasPostgres := false -}}
{{- range $index, $user := $users -}}
  {{- if eq $user.name "postgres" -}}
    {{- $hasPostgres = true -}}
  {{- end -}}
{{- end -}}

{{- if not $hasPostgres -}}
  {{- fail "The users array in postgrescluster must contain at least one user named 'postgres'." -}}
{{- end -}}

{{- end -}}

{{/*
validate:
that you can only use traefik as ingress when `testing=true`
*/}}
{{- define "eoapi.validateTraefik" -}}
{{- if and (not .Values.testing) (eq .Values.ingress.className "traefik") $ -}}
  {{- fail "you cannot use traefik yet outside of testing" -}}
{{- end -}}

{{- end -}}

{{/*
validate:
that you cannot have db.enabled and (postgrescluster.enabled or pgstacBootstrap.enabled)
*/}}
{{- define "eoapi.validateTempDB" -}}
{{- if and (.Values.db.enabled) (.Values.postgrescluster.enabled) -}}
  {{- fail "you cannot use have both db.enabled and postgresclsuter.enabled" -}}
{{- end -}}
{{- if and (.Values.db.enabled) (.Values.pgstacBootstrap.enabled) -}}
  {{- fail "you cannot use have both db.enabled and pgstacBootstrap.enabled" -}}
{{- end -}}

{{- end -}}