{{/*
Return true when API services should enable proxy header and root-path flags.
Only NGINX and Traefik ingress controllers are supported.
*/}}
{{- define "eoapi.ingressUsesProxyHeaders" -}}
{{- $class := .Values.ingress.className -}}
{{- if and $class (or (eq $class "nginx") (eq $class "traefik")) -}}true{{- end -}}
{{- end -}}

{{/*
Unified ingress service metadata. Drives path rendering and Traefik strip-prefix generation.
*/}}
{{- define "eoapi.ingressServiceEntries" -}}
{{- $entries := list
  (dict "key" "stac" "usesAuthProxy" true)
  (dict "key" "raster")
  (dict "key" "vector")
  (dict "key" "multidim")
  (dict "key" "browser" "defaultPath" "/browser" "hasOwnPort" true "skipStripPrefix" true)
  (dict "key" "mockOidcServer" "actualName" "mock-oidc-server" "hasOwnPort" true "valuesPath" (list "testing" "mockOidcServer"))
-}}
{{- toJson $entries -}}
{{- end -}}

{{/*
Return true when at least one service or doc server should be exposed via ingress.
*/}}
{{- define "eoapi.hasEnabledService" -}}
{{- $root := . -}}
{{- $hasService := false -}}
{{- range include "eoapi.ingressServiceEntries" $root | fromJsonArray }}
  {{- $entry := . -}}
  {{- $service := index $root.Values $entry.key -}}
  {{- if $entry.valuesPath }}
    {{- $service = $root.Values -}}
    {{- range $entry.valuesPath }}
      {{- $service = index $service . -}}
    {{- end }}
  {{- end }}
  {{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) }}
    {{- $hasService = true -}}
  {{- end }}
{{- end }}
{{- if or $hasService $root.Values.docServer.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Generate ingress path rules for enabled services.
*/}}
{{- define "eoapi.ingressPaths" -}}
{{- $root := . -}}
{{- $isNginx := eq $root.Values.ingress.className "nginx" -}}
{{- range include "eoapi.ingressServiceEntries" $root | fromJsonArray }}
  {{- $entry := . -}}
  {{- $service := index $root.Values $entry.key -}}
  {{- if $entry.valuesPath }}
    {{- $service = $root.Values -}}
    {{- range $entry.valuesPath }}
      {{- $service = index $service . -}}
    {{- end }}
  {{- end }}
  {{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) }}
    {{- $path := $service.ingress.path | default $entry.defaultPath -}}
    {{- $useAuthProxy := and $entry.usesAuthProxy (index $root.Values "stac-auth-proxy" "enabled") -}}
    {{- $stripPath := and (ne $path "/") (not $useAuthProxy) (not $entry.skipStripPrefix) -}}
    {{- $serviceName := $entry.actualName | default $entry.key -}}
    {{- $port := $root.Values.service.port -}}
    {{- if $entry.hasOwnPort }}
      {{- if $service.service }}
        {{- $port = $service.service.port | default 8080 }}
      {{- else }}
        {{- $port = 8080 }}
      {{- end }}
    {{- end }}
- pathType: {{ if and $isNginx $stripPath }}ImplementationSpecific{{ else }}Prefix{{ end }}
  path: {{ $path }}{{ if and $isNginx $stripPath }}(/|$)(.*){{ end }}
  backend:
    service:
      {{- if $useAuthProxy }}
      name: {{ $root.Release.Name }}-stac-auth-proxy
      {{- else }}
      name: {{ $root.Release.Name }}-{{ $serviceName }}
      {{- end }}
      port:
        number: {{ $port }}
  {{- end }}
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
{{- $root := . -}}
{{- $prefixes := list -}}
{{- range include "eoapi.ingressServiceEntries" $root | fromJsonArray }}
  {{- $entry := . -}}
  {{- $service := index $root.Values $entry.key -}}
  {{- if $entry.valuesPath }}
    {{- $service = $root.Values -}}
    {{- range $entry.valuesPath }}
      {{- $service = index $service . -}}
    {{- end }}
  {{- end }}
  {{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) }}
    {{- $useAuthProxy := and $entry.usesAuthProxy (index $root.Values "stac-auth-proxy" "enabled") -}}
    {{- $stripPath := not (or $entry.skipStripPrefix $useAuthProxy) -}}
    {{- if $stripPath }}
      {{- $path := $service.ingress.path | default $entry.defaultPath -}}
      {{- if $path }}
        {{- $prefixes = append $prefixes $path }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end -}}
{{- toJson $prefixes -}}
{{- end -}}

{{/*
Return the configured browser ingress path without trailing slash, or empty when unavailable.
*/}}
{{- define "eoapi.browserIngressPath" -}}
{{- $browser := .Values.browser -}}
{{- if and $browser $browser.enabled (or (not $browser.ingress) $browser.ingress.enabled) -}}
{{- trimSuffix "/" ($browser.ingress.path | default "/browser") -}}
{{- end -}}
{{- end -}}

{{/*
NGINX server-snippet that redirects bare browser path to trailing-slash form.
*/}}
{{- define "eoapi.nginxBrowserRedirectSnippet" -}}
{{- $path := include "eoapi.browserIngressPath" . | trim -}}
{{- if and $path (ne $path "/") -}}
location = {{ $path }} {
  return 301 {{ $path }}/;
}
{{- end -}}
{{- end -}}

{{/*
Comma-separated Traefik middleware references for the unified ingress router.
*/}}
{{- define "eoapi.ingressTraefikMiddlewares" -}}
{{- $root := . -}}
{{- $mwPrefix := printf "%s-%s" $root.Release.Namespace $root.Release.Name -}}
{{- $middlewares := list -}}
{{- if include "eoapi.traefikStripPrefixes" $root | fromJsonArray }}
{{- $middlewares = append $middlewares (printf "%s-strip-prefix-middleware@kubernetescrd" $mwPrefix) -}}
{{- end }}
{{- $browser := $root.Values.browser -}}
{{- if and $browser $browser.enabled (or (not $browser.ingress) $browser.ingress.enabled) }}
{{- $middlewares = append $middlewares (printf "%s-browser-redirect-middleware@kubernetescrd" $mwPrefix) -}}
{{- end }}
{{- join "," $middlewares -}}
{{- end -}}
