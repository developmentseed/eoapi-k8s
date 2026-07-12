{{/*
Return JSON array of enabled API ingress services with resolved path, backend, and rewrite metadata.
*/}}
{{- define "eoapi.enabledIngressServices" -}}
{{- $root := . -}}
{{- $entries := list
  (dict "key" "stac" "usesAuthProxy" true)
  (dict "key" "raster")
  (dict "key" "vector")
  (dict "key" "multidim")
  (dict "key" "mockOidcServer" "actualName" "mock-oidc-server" "hasOwnPort" true "defaultPath" "/mock-oidc")
-}}
{{- $resolved := list -}}
{{- range $entries }}
  {{- $entry := . -}}
  {{- $service := ternary (index $root.Values "testing" "mockOidcServer") (index $root.Values $entry.key) (eq $entry.key "mockOidcServer") -}}
  {{- $ingress := (($service | default dict).ingress) | default dict -}}
  {{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) }}
    {{- $path := $ingress.path | default $entry.defaultPath -}}
    {{- $useAuthProxy := and $entry.usesAuthProxy (index $root.Values "stac-auth-proxy" "enabled") -}}
    {{- $stripPath := and (ne $path "/") (not $useAuthProxy) -}}
    {{- $serviceName := $entry.actualName | default $entry.key -}}
    {{- $port := $root.Values.service.port -}}
    {{- if $entry.hasOwnPort }}
      {{- $port = (($service.service).port | default 8080) }}
    {{- end }}
    {{- $resolved = append $resolved (dict "path" $path "serviceName" $serviceName "port" $port "useAuthProxy" $useAuthProxy "stripPath" $stripPath) -}}
  {{- end }}
{{- end }}
{{- toJson $resolved -}}
{{- end -}}

{{/*
Return true when at least one API service or doc server should be exposed via the main ingress.
*/}}
{{- define "eoapi.hasEnabledService" -}}
{{- $root := . -}}
{{- if or (include "eoapi.enabledIngressServices" $root | fromJsonArray) $root.Values.docServer.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Ingress apiVersion based on cluster capabilities.
*/}}
{{- define "eoapi.ingressApiVersion" -}}
{{- if semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion -}}
networking.k8s.io/v1
{{- else if semverCompare ">=1.14-0" .Capabilities.KubeVersion.GitVersion -}}
networking.k8s.io/v1beta1
{{- else -}}
extensions/v1beta1
{{- end -}}
{{- end -}}

{{/*
Shared Traefik entrypoints and user annotations for ingress resources.
*/}}
{{- define "eoapi.ingressCommonAnnotations" -}}
{{- $root := . -}}
{{- $ingressAnnotations := $root.Values.ingress.annotations | default dict -}}
{{- if eq $root.Values.ingress.className "traefik" -}}
{{- if and $root.Values.ingress.entrypoints (not (hasKey $ingressAnnotations "traefik.ingress.kubernetes.io/router.entrypoints")) -}}
traefik.ingress.kubernetes.io/router.entrypoints: {{ $root.Values.ingress.entrypoints | quote }}
{{- end -}}
{{- end -}}
{{- if not (empty $ingressAnnotations) -}}
{{- toYaml $ingressAnnotations -}}
{{- end -}}
{{- end -}}

{{/*
Shared ingress rules block for host(s) and path lists.
*/}}
{{- define "eoapi.ingressRules" -}}
{{- $root := .root -}}
{{- $pathsTemplate := .pathsTemplate -}}
{{- if $root.Values.ingress.hosts }}
{{- range $root.Values.ingress.hosts }}
- host: {{ . }}
  http:
    paths:
      {{- include $pathsTemplate $root | nindent 6 }}
{{- end }}
{{- else }}
- {{- if $root.Values.ingress.host }}
  host: {{ $root.Values.ingress.host }}
  {{- end }}
  http:
    paths:
      {{- include $pathsTemplate $root | nindent 6 }}
{{- end }}
{{- end -}}

{{/*
Shared TLS block for ingress resources.
*/}}
{{- define "eoapi.ingressTls" -}}
{{- if and .Values.ingress.tls.enabled (or .Values.ingress.hosts .Values.ingress.host) }}
tls:
  - hosts:
      {{- if .Values.ingress.hosts }}
      {{- range .Values.ingress.hosts }}
      - {{ . }}
      {{- end }}
      {{- else if .Values.ingress.host }}
      - {{ .Values.ingress.host }}
      {{- end }}
    secretName: {{ .Values.ingress.tls.secretName }}
{{- end }}
{{- end -}}

{{/*
Generate ingress path rules for enabled API services and doc server.
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
{{- $root := . -}}
{{- $prefixes := list -}}
{{- range include "eoapi.enabledIngressServices" $root | fromJsonArray }}
  {{- if .stripPath }}
    {{- if .path }}
      {{- $prefixes = append $prefixes .path }}
    {{- end }}
  {{- end }}
{{- end }}
{{- toJson $prefixes -}}
{{- end -}}

{{/*
Return true when the browser should be exposed via its own ingress.
*/}}
{{- define "eoapi.browserIngressEnabled" -}}
{{- $browser := .Values.browser -}}
{{- if and .Values.ingress.enabled $browser $browser.enabled (or (not $browser.ingress) $browser.ingress.enabled) -}}true{{- end -}}
{{- end -}}

{{/*
Return the configured browser ingress path without trailing slash ("/" for a root path).
*/}}
{{- define "eoapi.browserIngressPath" -}}
{{- trimSuffix "/" (.Values.browser.ingress.path | default "/browser") | default "/" -}}
{{- end -}}

{{/*
Return the canonical browser path prefix with trailing slash, as served by the pod (SB_pathPrefix).
*/}}
{{- define "eoapi.browserPathPrefix" -}}
{{- $bare := include "eoapi.browserIngressPath" . -}}
{{- if eq $bare "/" -}}/{{- else -}}{{ $bare }}/{{- end -}}
{{- end -}}

{{/*
Return true when the Traefik bare-path redirect middleware is needed (non-root browser path).
*/}}
{{- define "eoapi.browserRedirectEnabled" -}}
{{- if and (include "eoapi.browserIngressEnabled" .) (ne (include "eoapi.browserIngressPath" .) "/") -}}true{{- end -}}
{{- end -}}

{{/*
Browser ingress path rule.
*/}}
{{- define "eoapi.browserIngressPaths" -}}
{{- $root := . -}}
- pathType: Prefix
  path: {{ include "eoapi.browserIngressPath" $root }}
  backend:
    service:
      name: {{ $root.Release.Name }}-browser
      port:
        number: {{ $root.Values.browser.service.port | default 8080 }}
{{- end -}}
