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
Resolve deployment git SHA: explicit value or chart version fallback.
Published charts inject gitSha into values at release time.
*/}}
{{- define "eoapi.gitSha" -}}
{{- $sha := .Values.gitSha -}}
{{- if or (not $sha) (eq $sha "gitshaABC123") -}}
{{- .Chart.Version -}}
{{- else -}}
{{- $sha -}}
{{- end -}}
{{- end -}}

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
Resolve a container image reference from an image values map.
Uses name + tag, or name@digest when digest is set.
*/}}
{{- define "eoapi.containerImage" -}}
{{- if .digest -}}
{{- printf "%s@%s" .name .digest -}}
{{- else -}}
{{- printf "%s:%s" .name (required "image.tag is required when digest is unset" .tag) -}}
{{- end -}}
{{- end -}}
