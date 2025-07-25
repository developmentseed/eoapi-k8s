{{- define "eoapi.pgstacInitContainer" -}}
{{- if .Values.pgstacBootstrap.enabled }}
- name: wait-for-pgstac-migrate
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
- name: wait-for-pgstac-load-samples
  image: bitnami/kubectl:latest
  command:
    - /bin/sh
    - -c
    - |
      echo "Waiting for pgstac-load-samples job to complete..."
      until kubectl get job pgstac-load-samples -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q "True"; do
        echo "pgstac-load-samples job not complete yet, waiting..."
        sleep 5
      done
      echo "pgstac-load-samples job completed successfully."
{{- end }}
{{- end }}
{{- end -}}
