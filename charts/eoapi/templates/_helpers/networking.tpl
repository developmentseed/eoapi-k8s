{{/*
Return JSON array of enabled ingress services with resolved path, backend, and rewrite metadata.
Browser remains on the main ingress; skipStripPrefix excludes it from Traefik strip-prefix only.
*/}}
{{- define "eoapi.enabledIngressServices" -}}
{{- $root := . -}}
{{- $entries := list
  (dict "key" "stac" "usesAuthProxy" true)
  (dict "key" "raster")
  (dict "key" "vector")
  (dict "key" "multidim")
  (dict "key" "browser" "defaultPath" "/browser" "hasOwnPort" true "skipStripPrefix" true)
  (dict "key" "mockOidcServer" "actualName" "mock-oidc-server" "hasOwnPort" true)
-}}
{{- $resolved := list -}}
{{- range $entries }}
  {{- $entry := . -}}
  {{- $service := ternary (index $root.Values "testing" "mockOidcServer") (index $root.Values $entry.key) (eq $entry.key "mockOidcServer") -}}
  {{- $ingress := (($service | default dict).ingress) | default dict -}}
  {{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) }}
    {{- $path := $ingress.path | default $entry.defaultPath -}}
    {{- $useAuthProxy := and $entry.usesAuthProxy (index $root.Values "stac-auth-proxy" "enabled") -}}
    {{/* nginxStrip: NGINX rewrite path shape; stripPrefix: Traefik middleware (matches main, includes "/") */}}
    {{- $nginxStrip := and (ne $path "/") (not $useAuthProxy) -}}
    {{- $stripPrefix := and (not $entry.skipStripPrefix) (not $useAuthProxy) -}}
    {{- $serviceName := $entry.actualName | default $entry.key -}}
    {{- $port := $root.Values.service.port -}}
    {{- if $entry.hasOwnPort }}
      {{- $port = (($service.service).port | default 8080) }}
    {{- end }}
    {{- $resolved = append $resolved (dict "path" $path "serviceName" $serviceName "port" $port "useAuthProxy" $useAuthProxy "stripPath" $nginxStrip "stripPrefix" $stripPrefix) -}}
  {{- end }}
{{- end }}
{{- toJson $resolved -}}
{{- end -}}

{{/*
Return true when at least one ingress service or doc server is enabled.
*/}}
{{- define "eoapi.hasEnabledService" -}}
{{- if or (include "eoapi.enabledIngressServices" . | fromJsonArray) .Values.docServer.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Generate ingress path rules for enabled services and doc server.
*/}}
{{- define "eoapi.ingressPaths" -}}
{{- $root := . -}}
{{- $isNginx := eq $root.Values.ingress.className "nginx" -}}
{{- range include "eoapi.enabledIngressServices" $root | fromJsonArray }}
- pathType: {{ if and $isNginx .stripPath }}ImplementationSpecific{{ else }}Prefix{{ end }}
  path: {{ .path }}{{ if and $isNginx .stripPath }}(/|$)(.*){{ end }}
  backend:
    service:
      {{- if .useAuthProxy }}
      name: {{ $root.Release.Name }}-stac-auth-proxy
      {{- else }}
      name: {{ $root.Release.Name }}-{{ .serviceName }}
      {{- end }}
      port:
        number: {{ .port }}
{{- end }}
{{- if $root.Values.docServer.enabled }}
- pathType: Prefix
  path: "/{{ $root.Values.ingress.rootPath | default "" }}"
  backend:
    service:
      name: {{ $root.Release.Name }}-doc-server
      port:
        number: 80
{{- end }}
{{- end -}}

{{/*
Return JSON array of path prefixes for Traefik strip-prefix middleware.
*/}}
{{- define "eoapi.traefikStripPrefixes" -}}
{{- $prefixes := list -}}
{{- range include "eoapi.enabledIngressServices" . | fromJsonArray }}
  {{- if and .stripPrefix .path }}
    {{- $prefixes = append $prefixes .path }}
  {{- end }}
{{- end }}
{{- toJson $prefixes -}}
{{- end -}}

{{/*
Return the configured browser ingress path without trailing slash.
*/}}
{{- define "eoapi.browserIngressPath" -}}
{{- trimSuffix "/" ((((.Values.browser).ingress).path) | default "/browser") | default "/" -}}
{{- end -}}

{{/*
Return true when the Traefik bare-path redirect middleware is needed.
*/}}
{{- define "eoapi.browserRedirectEnabled" -}}
{{- $browser := .Values.browser -}}
{{- if and $browser $browser.enabled (or (not $browser.ingress) $browser.ingress.enabled) -}}true{{- end -}}
{{- end -}}
