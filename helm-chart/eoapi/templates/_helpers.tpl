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
{{- define "eoapi.pgstacHostName" -}}
{{- if .Values.testing }}
{{- printf "%s-%s" "pgstac" .Release.Name }}
{{- else }}
{{/* need to match what is default in values.yamls */}}
{{- printf "%s" "pgstac" }}
{{- end }}
{{- end }}

{{/*
values.schema.json doesn't play nice combined value checks
so we use this helper function to check autoscaling rules
*/}}
{{- define "eoapi.validateAutoscaleRules" -}}
{{- if and .Values.ingress.enabled (ne .Values.ingress.className "nginx") }}
    {{/* "requestRate" cannot be enabled for any service if not "nginx" so give feedback and fail */}}
    {{- if (or
        (and .Values.raster.autoscaling.enabled (eq .Values.raster.autoscaling.type "requestRate"))
        (and .Values.stac.autoscaling.enabled (eq .Values.stac.autoscaling.type "requestRate"))
        (and .Values.vector.autoscaling.enabled (eq .Values.vector.autoscaling.type "requestRate"))
    ) }}
        {{- fail "When using an 'ingress.className' other than 'nginx' you cannot enable autoscaling by 'requestRate' at this time b/c it's solely an nginx metric" }}
    {{- end }}

    {{/* "host" has to be empty if not "nginx" so give feedback and fail */}}
    {{- if .Values.ingress.host }}
        {{- fail "When using an 'ingress.className' other than 'nginx' you cannot provision a 'host' at this time" }}
    {{- end }}

    {{/* "tls" cannot be enabled if not "nginx" so give feedback and fail */}}
    {{- if .Values.ingress.tls.enabled }}
        {{- fail "When using an 'ingress.className' other than 'nginx' you cannot enable 'tls' at this time" }}
    {{- end }}
{{- end }} {{/* if and .Values.ingress.enabled (ne .Values.ingress.className "nginx") /*}}
{{- end -}} {{/* define */}}

