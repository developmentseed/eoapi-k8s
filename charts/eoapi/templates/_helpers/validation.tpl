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
Ensure prometheus-adapter custom metric names match HPA request-rate metrics.
*/}}
{{- define "eoapi.validateHpaAdapterMetricAlignment" -}}
{{- if .Values.monitoring.prometheusAdapter.enabled }}
{{- $adapter := index .Values "prometheus-adapter" | default dict }}
{{- $rules := list }}
{{- if and $adapter.rules $adapter.rules.custom }}
{{- $rules = $adapter.rules.custom }}
{{- end }}
{{- range .Values.apiServices }}
{{- $service := . }}
{{- $autoscaling := index $.Values $service "autoscaling" | default dict }}
{{- if and $autoscaling.enabled (or (eq $autoscaling.type "requestRate") (eq $autoscaling.type "both")) }}
{{- $expected := include "eoapi.hpaRequestRateMetricName" (dict "service" $service) | trim }}
{{- $found := false }}
{{- range $rules }}
{{- if and .name .name.as (eq .name.as $expected) }}
{{- $found = true }}
{{- end }}
{{- end }}
{{- if not $found }}
{{- fail (printf "prometheus-adapter.rules.custom must define name.as %q for request-rate HPA (service %q). See eoapi.hpaRequestRateMetricName in _helpers/services.tpl" $expected $service) }}
{{- end }}
{{- end }}
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

{{/*
Validate browser ingress path matches the bundled image pathPrefix.
*/}}
{{- define "eoapi.validateBrowserIngress" -}}
{{- $browser := .Values.browser -}}
{{- if and $browser $browser.enabled -}}
{{- $ingress := $browser.ingress | default dict -}}
{{- if and (default true $ingress.enabled) $ingress.path -}}
{{- $path := trimSuffix "/" $ingress.path -}}
{{- if ne $path "/browser" }}
{{- fail "browser.ingress.path must be \"/browser\" (or \"/browser/\"). The bundled browser image is built with pathPrefix=/browser/." }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Validate API ingress paths: must start with / and must not have trailing slashes except root.
*/}}
{{- define "eoapi.validateApiIngressPath" -}}
{{- $path := .path -}}
{{- $label := .label -}}
{{- if not (hasPrefix "/" $path) }}
{{- fail (printf "%s must start with \"/\" (got %q)" $label $path) }}
{{- end }}
{{- if and (ne $path "/") (hasSuffix "/" $path) }}
{{- fail (printf "%s must not have a trailing slash except \"/\" (got %q)" $label $path) }}
{{- end }}
{{- end -}}

{{/*
Validate ingress paths for enabled API services and testing mock OIDC server.
*/}}
{{- define "eoapi.validateIngressPaths" -}}
{{- $root := . -}}
{{- range $root.Values.apiServices }}
{{- $service := index $root.Values . -}}
{{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) $service.ingress.path }}
{{- include "eoapi.validateApiIngressPath" (dict "path" $service.ingress.path "label" (printf "%s.ingress.path" .)) }}
{{- end }}
{{- end }}
{{- $mock := $root.Values.testing.mockOidcServer | default dict -}}
{{- if and $mock.enabled (or (not $mock.ingress) $mock.ingress.enabled) $mock.ingress.path }}
{{- include "eoapi.validateApiIngressPath" (dict "path" $mock.ingress.path "label" "testing.mockOidcServer.ingress.path") }}
{{- end }}
{{- end -}}

{{/*
Require a usable ingress host when browser auto-constructs catalog or auth URLs.
*/}}
{{- define "eoapi.validateBrowserIngressHost" -}}
{{- $browser := .Values.browser -}}
{{- $needsHost := false -}}
{{- if and $browser $browser.enabled -}}
{{- if not $browser.catalogUrl }}
{{- $needsHost = true -}}
{{- end }}
{{- if and (index .Values "stac-auth-proxy" "enabled") (not $browser.authConfig) }}
{{- $needsHost = true -}}
{{- end }}
{{- if and $needsHost (not (include "eoapi.ingressPrimaryHost" . | trim)) }}
{{- fail "browser requires ingress.host or ingress.hosts[0] when browser.catalogUrl and browser.authConfig are unset and default URLs are used" }}
{{- end }}
{{- end }}
{{- end -}}
