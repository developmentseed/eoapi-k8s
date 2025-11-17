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
