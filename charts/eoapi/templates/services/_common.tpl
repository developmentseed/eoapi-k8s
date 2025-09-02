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
    
    BOOTSTRAP_JOB="pgstac-eoapi-superuser-init-db"
    MIGRATE_JOB="${RELEASE_NAME:-eoapi}-pgstac-migrate"
    SAMPLES_JOB="${RELEASE_NAME:-eoapi}-pgstac-load-samples"
    
    wait_complete () {
      job="$1"
      echo "Waiting for $job to complete..."
      deadline=$(( $(date +%s) + 900 ))
      while :; do
        conds="$(kubectl get job "$job" -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' 2>/dev/null || true)"
        echo "$conds" | grep -q '^Complete=True$' && { echo "$job completed"; return 0; }
        echo "$conds" | grep -q '^Failed=True$'   && {
          echo "$job FAILED"; kubectl describe job "$job" || true
          kubectl logs -l job-name="$job" --tail=200 || true
          exit 1
        }
        [ $(date +%s) -ge $deadline ] && { echo "Timeout waiting for $job"; exit 1; }
        sleep 5
      done
    }
    
    wait_complete "$BOOTSTRAP_JOB"
    wait_complete "$MIGRATE_JOB"
    {{- if .Values.pgstacBootstrap.settings.loadSamples }}
    wait_complete "$SAMPLES_JOB"
    {{- end }}
{{- end }}
{{- end -}}
