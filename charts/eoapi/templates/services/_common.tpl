{{/* 
Helper function for mounting service secrets
Only extract truly common elements that are mechanical and don't need customization
*/}}
{{- define "eoapi.mountServiceSecrets" -}}
{{- $service := .service -}}
{{- $root := .root -}}
{{- if index $root.Values $service "settings" "envSecrets" }}
{{- range $secret := index $root.Values $service "settings" "envSecrets" }}
- secretRef:
    name: {{ $secret }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Helper function for common environment variables
*/}}
{{- define "eoapi.commonEnvVars" -}}
{{- $service := .service -}}
{{- $root := .root -}}
- name: SERVICE_NAME
  value: {{ $service | quote }}
- name: RELEASE_NAME
  value: {{ $root.Release.Name | quote }}
- name: GIT_SHA
  value: {{ $root.Values.gitSha | quote }}
{{- end -}}

{{/*
Helper function for common init containers to wait for pgstac jobs
*/}}
{{- define "eoapi.pgstacInitContainers" -}}
{{- if .Values.pgstacBootstrap.enabled }}
initContainers:
- name: wait-for-pgstac-jobs
  image: bitnami/kubectl:latest
  command:
  - /bin/sh
  - -c
  - |
    echo "Waiting for pgstac-migrate job to complete..."
    until kubectl get job pgstac-migrate -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q "True"; do
      echo "pgstac-migrate job not complete yet, waiting..."
      sleep 5
    done
    echo "pgstac-migrate job completed successfully."
    
    {{- if .Values.pgstacBootstrap.settings.loadSamples }}
    echo "Waiting for pgstac-load-samples job to complete..."
    until kubectl get job pgstac-load-samples -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q "True"; do
      echo "pgstac-load-samples job not complete yet, waiting..."
      sleep 5
    done
    echo "pgstac-load-samples job completed successfully."
    {{- end }}
{{- end }}
{{- end -}}
