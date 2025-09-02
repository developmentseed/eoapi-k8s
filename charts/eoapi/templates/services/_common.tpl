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
  env:
  {{- include "eoapi.commonEnvVars" (dict "service" "init" "root" .) | nindent 2 }}
  command:
  - /bin/sh
  - -c
  - |
    set -eu
    
    MIGRATE_JOB="${RELEASE_NAME:-eoapi}-pgstac-migrate"
    SAMPLES_JOB="${RELEASE_NAME:-eoapi}-pgstac-load-samples"
    
    wait_complete () {
      job="$1"
      echo "Waiting for $job to complete..."
      # Optional: fail fast after 15 min so CI doesn't hang forever
      deadline=$(( $(date +%s) + 900 ))
      while :; do
        # If job doesn't exist yet or SA can't read it, jsonpath may be empty
        status="$(kubectl get job "$job" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)"
        [ "$status" = "True" ] && { echo "$job completed"; return 0; }
        [ $(date +%s) -ge $deadline ] && { echo "Timeout waiting for $job"; exit 1; }
        sleep 5
      done
    }
    
    wait_complete "$MIGRATE_JOB"
    {{- if .Values.pgstacBootstrap.settings.loadSamples }}
    wait_complete "$SAMPLES_JOB"
    {{- end }}
{{- end }}
{{- end -}}
