{{/*
Common resource definitions to avoid duplication across values files
*/}}

{{/*
Small resource allocation for lightweight components
*/}}
{{- define "eoapi.resources.small" -}}
limits:
  cpu: 10m
  memory: 30Mi
requests:
  cpu: 10m
  memory: 30Mi
{{- end -}}

{{/*
Medium resource allocation for standard services
*/}}
{{- define "eoapi.resources.medium" -}}
limits:
  cpu: 100m
  memory: 128Mi
requests:
  cpu: 50m
  memory: 64Mi
{{- end -}}

{{/*
Large resource allocation for heavy workloads
*/}}
{{- define "eoapi.resources.large" -}}
limits:
  cpu: 500m
  memory: 512Mi
requests:
  cpu: 250m
  memory: 256Mi
{{- end -}}

{{/*
Grafana specific resources based on observed usage patterns
*/}}
{{- define "eoapi.resources.grafana" -}}
limits:
  cpu: 100m
  memory: 200Mi
requests:
  cpu: 50m
  memory: 100Mi
{{- end -}}
