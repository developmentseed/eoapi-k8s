{{/*
Fetch the CA Bundle from a specified secret if enabled
*/}}
{{- define "eoapi-support.fetchCaBundle" -}}
{{- if .Values.enableCaBundleFetch -}}
  {{- $secretName := .Values.caBundleSecretName | default "eoepca-ca-secret" -}}
  {{- $caBundle := "" -}}
  {{- with (lookup "v1" "Secret" "default" $secretName) -}}
    {{- $caBundle = index .data "ca.crt" | b64dec -}}
  {{- end -}}
  {{- $caBundle -}}
{{- else -}}
  ""  # Return an empty string if not enabled
{{- end -}}
{{- end -}}
