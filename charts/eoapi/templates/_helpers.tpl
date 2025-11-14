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
PostgreSQL environment variables based on the configured type
*/}}
{{- define "eoapi.postgresqlEnv" -}}
{{- if eq .Values.postgresql.type "postgrescluster" }}
  {{- include "eoapi.postgresclusterSecrets" . }}
{{- else if eq .Values.postgresql.type "external-plaintext" }}
  {{- include "eoapi.externalPlaintextPgSecrets" . }}
{{- else if eq .Values.postgresql.type "external-secret" }}
  {{- include "eoapi.externalSecretPgSecrets" . }}
{{- end }}
{{- end }}

{{/*
PostgreSQL cluster secrets
*/}}
{{- define "eoapi.postgresclusterSecrets" -}}
{{- range $userName, $v := .Values.postgrescluster.users -}}
{{/* do not render anything for the "postgres" user */}}
{{- if not (eq (index $v "name") "postgres") }}
# Standard PostgreSQL environment variables
- name: PGUSER
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: user
- name: PGPORT
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: port
- name: PGHOST
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: password
- name: PGDATABASE
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: dbname
- name: PGBOUNCER_URI
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: pgbouncer-uri
# Legacy variables for backward compatibility
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: user
- name: POSTGRES_PORT
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: port
- name: POSTGRES_HOST
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: POSTGRES_HOST_READER
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: POSTGRES_HOST_WRITER
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: host
- name: POSTGRES_PASS
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: password
- name: POSTGRES_DBNAME
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: dbname
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.postgrescluster.name | default $.Release.Name }}-pguser-{{ index $v "name" }}
      key: uri
{{- end }}
{{- end }}
- name: PGADMIN_URI
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgrescluster.name | default .Release.Name }}-pguser-postgres
      key: uri
{{- end }}

{{/*
External PostgreSQL with plaintext credentials
*/}}
{{- define "eoapi.externalPlaintextPgSecrets" -}}
# Standard PostgreSQL environment variables
- name: PGUSER
  value: {{ .Values.postgresql.external.credentials.username | quote }}
- name: PGPORT
  value: {{ .Values.postgresql.external.port | quote }}
- name: PGHOST
  value: {{ .Values.postgresql.external.host | quote }}
- name: PGPASSWORD
  value: {{ .Values.postgresql.external.credentials.password | quote }}
- name: PGDATABASE
  value: {{ .Values.postgresql.external.database | quote }}
# Legacy variables for backward compatibility
- name: POSTGRES_USER
  value: {{ .Values.postgresql.external.credentials.username | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.postgresql.external.port | quote }}
- name: POSTGRES_HOST
  value: {{ .Values.postgresql.external.host | quote }}
- name: POSTGRES_HOST_READER
  value: {{ .Values.postgresql.external.host | quote }}
- name: POSTGRES_HOST_WRITER
  value: {{ .Values.postgresql.external.host | quote }}
- name: POSTGRES_PASS
  value: {{ .Values.postgresql.external.credentials.password | quote }}
- name: POSTGRES_DBNAME
  value: {{ .Values.postgresql.external.database | quote }}
- name: DATABASE_URL
  value: "postgresql://{{ .Values.postgresql.external.credentials.username }}:{{ .Values.postgresql.external.credentials.password }}@{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}"
{{- end }}

{{/*
External PostgreSQL with secret credentials
*/}}
{{- define "eoapi.externalSecretPgSecrets" -}}
# Standard PostgreSQL environment variables
- name: PGUSER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.username }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.password }}
# Legacy variables for backward compatibility
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.username }}
- name: POSTGRES_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.password }}

# Host, port, and database can be from the secret or from values
{{- if .Values.postgresql.external.existingSecret.keys.host }}
- name: PGHOST
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.host }}
- name: POSTGRES_HOST
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.host }}
- name: POSTGRES_HOST_READER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.host }}
- name: POSTGRES_HOST_WRITER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.host }}
{{- else }}
- name: PGHOST
  value: {{ .Values.postgresql.external.host | quote }}
- name: POSTGRES_HOST
  value: {{ .Values.postgresql.external.host | quote }}
- name: POSTGRES_HOST_READER
  value: {{ .Values.postgresql.external.host | quote }}
- name: POSTGRES_HOST_WRITER
  value: {{ .Values.postgresql.external.host | quote }}
{{- end }}

{{- if .Values.postgresql.external.existingSecret.keys.port }}
- name: PGPORT
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.port }}
- name: POSTGRES_PORT
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.port }}
{{- else }}
- name: PGPORT
  value: {{ .Values.postgresql.external.port | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.postgresql.external.port | quote }}
{{- end }}

{{- if .Values.postgresql.external.existingSecret.keys.database }}
- name: PGDATABASE
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.database }}
- name: POSTGRES_DBNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.database }}
{{- else }}
- name: PGDATABASE
  value: {{ .Values.postgresql.external.database | quote }}
- name: POSTGRES_DBNAME
  value: {{ .Values.postgresql.external.database | quote }}
{{- end }}

# Add DATABASE_URL for connection string
{{- if .Values.postgresql.external.existingSecret.keys.uri }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.external.existingSecret.name }}
      key: {{ .Values.postgresql.external.existingSecret.keys.uri }}
{{- else }}
- name: DATABASE_URL
  value: "postgresql://$(PGUSER):$(PGPASSWORD)@$(PGHOST):$(PGPORT)/$(PGDATABASE)"
{{- end }}
{{- end }}

{{/*
Validate PostgreSQL configuration
*/}}
{{- define "eoapi.validatePostgresql" -}}
{{- if eq .Values.postgresql.type "postgrescluster" }}
  {{- if not .Values.postgrescluster.enabled }}
    {{- fail "When postgresql.type is 'postgrescluster', postgrescluster.enabled must be true" }}
  {{- end }}
  {{- include "eoapi.validatePostgresCluster" . }}
{{- else if eq .Values.postgresql.type "external-plaintext" }}
  {{- if .Values.postgrescluster.enabled }}
    {{- fail "When postgresql.type is 'external-plaintext', postgrescluster.enabled must be set to false" }}
  {{- end }}
  {{- if not .Values.postgresql.external.host }}
    {{- fail "When postgresql.type is 'external-plaintext', postgresql.external.host must be set" }}
  {{- end }}
  {{- if not .Values.postgresql.external.credentials.username }}
    {{- fail "When postgresql.type is 'external-plaintext', postgresql.external.credentials.username must be set" }}
  {{- end }}
  {{- if not .Values.postgresql.external.credentials.password }}
    {{- fail "When postgresql.type is 'external-plaintext', postgresql.external.credentials.password must be set" }}
  {{- end }}
{{- else if eq .Values.postgresql.type "external-secret" }}
  {{- if .Values.postgrescluster.enabled }}
    {{- fail "When postgresql.type is 'external-secret', postgrescluster.enabled must be set to false" }}
  {{- end }}
  {{- if not .Values.postgresql.external.existingSecret.name }}
    {{- fail "When postgresql.type is 'external-secret', postgresql.external.existingSecret.name must be set" }}
  {{- end }}
  {{- if not .Values.postgresql.external.existingSecret.keys.username }}
    {{- fail "When postgresql.type is 'external-secret', postgresql.external.existingSecret.keys.username must be set" }}
  {{- end }}
  {{- if not .Values.postgresql.external.existingSecret.keys.password }}
    {{- fail "When postgresql.type is 'external-secret', postgresql.external.existingSecret.keys.password must be set" }}
  {{- end }}
  {{- if not .Values.postgresql.external.existingSecret.keys.host }}
    {{- if not .Values.postgresql.external.host }}
      {{- fail "When postgresql.type is 'external-secret' and existingSecret.keys.host is not set, postgresql.external.host must be set" }}
    {{- end }}
  {{- end }}
{{- else }}
  {{- fail "postgresql.type must be one of: 'postgrescluster', 'external-plaintext', 'external-secret'" }}
{{- end }}
{{- end }}

{{/*
values.schema.json doesn't play nice combined value checks
so we use this helper function to check autoscaling rules
*/}}
{{- define "eoapi.validateAutoscaleRules" -}}
{{- if and .Values.ingress.enabled (ne .Values.ingress.className "nginx") }}
{{/* "requestRate" cannot be enabled for any service if not "nginx" so give feedback and fail */}}
{{- $requestRateEnabled := false }}
{{- range .Values.apiServices }}
{{- if and (index $.Values . "autoscaling" "enabled") (eq (index $.Values . "autoscaling" "type") "requestRate") }}
{{- $requestRateEnabled = true }}
{{- end }}
{{- end }}
{{- if $requestRateEnabled }}
{{- fail "When using an 'ingress.className' other than 'nginx' you cannot enable autoscaling by 'requestRate' at this time b/c it's solely an nginx metric" }}
{{- end }}
{{/* "both" cannot be enabled for any service if not "nginx" so give feedback and fail */}}
{{- $bothEnabled := false }}
{{- range .Values.apiServices }}
{{- if and (index $.Values . "autoscaling" "enabled") (eq (index $.Values . "autoscaling" "type") "both") }}
{{- $bothEnabled = true }}
{{- end }}
{{- end }}
{{- if $bothEnabled }}
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
