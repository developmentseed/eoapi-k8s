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

{{/*
Validate stac-auth-proxy configuration
Ensures OIDC_DISCOVERY_URL is set when stac-auth-proxy is enabled
Ensures stac-auth-proxy cannot be enabled when stac is disabled
*/}}
{{- define "eoapi.validateStacAuthProxy" -}}
{{- if index .Values "stac-auth-proxy" "enabled" }}
{{- if not .Values.stac.enabled }}
{{- fail "stac-auth-proxy cannot be enabled when stac.enabled is false. Enable stac first or disable stac-auth-proxy." }}
{{- end }}
{{- if not (index .Values "stac-auth-proxy" "env" "OIDC_DISCOVERY_URL") }}
{{- fail "stac-auth-proxy.env.OIDC_DISCOVERY_URL is required when stac-auth-proxy is enabled. Set it to your OpenID Connect discovery URL (e.g., https://your-auth-server/.well-known/openid-configuration)" }}
{{- end }}
{{- end }}
{{- end -}}
