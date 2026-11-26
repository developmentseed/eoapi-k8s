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
  value: {{ include "eoapi.gitSha" $root | quote }}
{{- end -}}

{{/*
prometheus_client multiprocess mode: without it each uvicorn worker (WEB_CONCURRENCY) keeps its own
registry and a scrape returns one worker's counters. Steps back when the user sets
PROMETHEUS_MULTIPROC_DIR in settings.envVars. No wipe needed: the emptyDir is new per pod, and
after a container restart the counters and histograms carry on from the old files.
Call with dict "service" <key> "root" $ "enabled" <metrics on> "part" "env"|"volumeMount"|"volume".
*/}}
{{- define "eoapi.metricsMultiproc" -}}
{{- $svc := index .root.Values .service -}}
{{- $userSet := false -}}
{{- range $k, $_ := $svc.settings.envVars }}{{ if eq (upper $k) "PROMETHEUS_MULTIPROC_DIR" }}{{ $userSet = true }}{{ end }}{{ end -}}
{{- if and .enabled (ne (toString $svc.metrics.multiprocess) "false") (not $userSet) -}}
{{- if eq .part "env" }}
- name: PROMETHEUS_MULTIPROC_DIR
  value: /tmp/prometheus-multiproc
{{- else if eq .part "volumeMount" }}
- name: prometheus-multiproc
  mountPath: /tmp/prometheus-multiproc
{{- else if eq .part "volume" }}
- name: prometheus-multiproc
  emptyDir: {}
{{- end }}
{{- end }}
{{- end -}}

{{/*
STAC API URL for raster.backend=stacapi: explicit value, else stac-auth-proxy (which serves under its ROOT_PATH) if enabled, else the stac service
*/}}
{{- define "eoapi.raster.stacApiUrl" -}}
{{- if .Values.raster.stacapi.stacApiUrl -}}
{{- .Values.raster.stacapi.stacApiUrl -}}
{{- else if index .Values "stac-auth-proxy" "enabled" -}}
{{- $proxy := index .Values "stac-auth-proxy" -}}
{{- printf "http://%s-stac-auth-proxy:%v%s" .Release.Name $proxy.service.port ($proxy.env.ROOT_PATH | default "") -}}
{{- else -}}
{{- printf "http://%s-stac:%v" .Release.Name .Values.service.port -}}
{{- end -}}
{{- end -}}

{{/*
Return prometheus-adapter custom metric name for request-rate HPA per service.
Canonical source for name.as in prometheus-adapter.rules.custom (values.yaml).
Validated at render time by eoapi.validateHpaAdapterMetricAlignment.
*/}}
{{- define "eoapi.hpaRequestRateMetricName" -}}
{{- printf "nginx_ingress_controller_requests_rate_%s_eoapi" .service -}}
{{- end -}}

{{/*
Helper function for common init containers to wait for pgstac jobs
*/}}
{{- define "eoapi.pgstacInitContainers" -}}
{{- if .Values.pgstacBootstrap.enabled }}
initContainers:
- name: wait-for-pgstac-jobs
  image: {{ include "eoapi.containerImage" .Values.pgstacBootstrap.waitImage }}
  imagePullPolicy: {{ .Values.pgstacBootstrap.waitImage.pullPolicy | default "IfNotPresent" }}
  {{- with .Values.pgstacBootstrap.settings.initContainerSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  env:
  {{- include "eoapi.commonEnvVars" (dict "service" "init" "root" .) | nindent 2 }}
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "100m"
      memory: "128Mi"
  command:
  - /bin/sh
  - -c
  - |
    set -eu

    # Configurable parameters with values.yaml support and environment variable fallback
    SLEEP_INTERVAL="${PGSTAC_WAIT_SLEEP_INTERVAL:-{{ .Values.pgstacBootstrap.settings.waitConfig.sleepInterval | default 5 }}}"
    TIMEOUT_SECONDS="${PGSTAC_WAIT_TIMEOUT:-{{ .Values.pgstacBootstrap.settings.waitConfig.timeout | default 900 }}}"

    wait_for_job_by_label () {
      label_selector="$1"
      job_description="$2"
      echo "Waiting for job with label $label_selector to complete (timeout: ${TIMEOUT_SECONDS}s, interval: ${SLEEP_INTERVAL}s)..."
      deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))

      while :; do
        # Check if deadline exceeded
        [ $(date +%s) -ge $deadline ] && { echo "Timeout waiting for $job_description job"; exit 1; }

        # Get jobs matching the label
        jobs=$(kubectl get job -l "$label_selector" -o name 2>/dev/null || true)

        if [ -z "$jobs" ]; then
          echo "No $job_description jobs found yet, waiting..."
          sleep 5
          continue
        fi

        # Check each job's status
        all_complete=true
        any_failed=false

        for job in $jobs; do
          # Get completion and failure status
          complete_status=$(kubectl get "$job" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
          failed_status=$(kubectl get "$job" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "False")

          job_name=$(echo "$job" | cut -d'/' -f2)

          if [ "$failed_status" = "True" ]; then
            echo "ERROR: $job_description job $job_name failed!"
            echo "Job details:"
            kubectl describe "$job" || true
            echo "Job logs:"
            kubectl logs -l "job-name=$job_name" --tail=50 || true
            any_failed=true
          elif [ "$complete_status" != "True" ]; then
            echo "$job_description job $job_name not yet complete (Complete: $complete_status, Failed: $failed_status)"
            all_complete=false
          else
            echo "$job_description job $job_name completed successfully"
          fi
        done

        # Exit with error if any job failed
        [ "$any_failed" = true ] && exit 1

        # Exit successfully if all jobs completed
        [ "$all_complete" = true ] && return 0

        sleep $SLEEP_INTERVAL
      done
    }

    wait_for_job_by_label "app={{ .Release.Name }}-pgstac-migrate" "pgstac-migrate"
    {{- if .Values.pgstacBootstrap.settings.loadSamples }}
    wait_for_job_by_label "app={{ .Release.Name }}-pgstac-load-samples" "pgstac-load-samples"
    {{- end }}
{{- end }}
{{- end -}}
