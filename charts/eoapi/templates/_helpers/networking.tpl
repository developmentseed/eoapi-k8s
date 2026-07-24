{{/*
Return JSON array of enabled API ingress services with resolved path, backend, and rewrite metadata.
Browser is intentionally excluded; it uses its own rewrite-free ingress.
*/}}
{{- define "eoapi.enabledIngressServices" -}}
{{- $root := . -}}
{{- $entries := list
  (dict "key" "stac" "usesAuthProxy" true)
  (dict "key" "raster")
  (dict "key" "vector")
  (dict "key" "multidim")
  (dict "key" "mockOidcServer" "actualName" "mock-oidc-server" "hasOwnPort" true "defaultPath" "/mock-oidc" "config" $root.Values.testing.mockOidcServer)
-}}
{{- $resolved := list -}}
{{- range $entries }}
  {{- $entry := . -}}
  {{- $service := $entry.config | default (index $root.Values $entry.key) -}}
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
Compute ingress gating flags and Traefik strip-prefixes in one pass.
Returns JSON: mainIngress, passthroughIngress, nginxRewrite, stripPrefixes.
*/}}
{{- define "eoapi.ingressFlags" -}}
{{- $root := . -}}
{{- $services := include "eoapi.enabledIngressServices" $root | fromJsonArray -}}
{{- $isNginx := eq $root.Values.ingress.className "nginx" -}}
{{- $hasNonAuth := false -}}
{{- $hasAuthProxy := false -}}
{{- $nginxRewrite := false -}}
{{- $prefixes := list -}}
{{- range $services }}
  {{- if .useAuthProxy }}{{ $hasAuthProxy = true }}{{ else }}{{ $hasNonAuth = true }}{{ end -}}
  {{- if .stripPath }}
    {{- $nginxRewrite = true -}}
    {{- if .path }}{{ $prefixes = append $prefixes .path }}{{ end -}}
  {{- end -}}
{{- end -}}
{{- $mainIngress := false -}}
{{- if $isNginx -}}
  {{- if or $hasNonAuth $root.Values.docServer.enabled }}{{ $mainIngress = true }}{{ end -}}
{{- else -}}
  {{- if or $hasNonAuth $hasAuthProxy $root.Values.docServer.enabled }}{{ $mainIngress = true }}{{ end -}}
{{- end -}}
{{- toJson (dict
  "mainIngress" $mainIngress
  "passthroughIngress" (and $isNginx $hasAuthProxy)
  "nginxRewrite" $nginxRewrite
  "stripPrefixes" $prefixes
) -}}
{{- end -}}

{{/*
Shared ingress annotations: entrypoints, user annotations, then chart-owned keys (last wins).
Call with dict "root" . "owned" <dict> "omit" <list> — omit drops keys after merge.
*/}}
{{- define "eoapi.ingressCommonAnnotations" -}}
{{- $root := .root -}}
{{- $owned := .owned | default dict -}}
{{- $annotations := dict -}}
{{- if and (eq $root.Values.ingress.className "traefik") $root.Values.ingress.entrypoints -}}
{{- $_ := set $annotations "traefik.ingress.kubernetes.io/router.entrypoints" ($root.Values.ingress.entrypoints | toString) -}}
{{- end -}}
{{- $annotations = mergeOverwrite $annotations ($root.Values.ingress.annotations | default dict) -}}
{{- $annotations = mergeOverwrite $annotations $owned -}}
{{- range (.omit | default list) }}{{ $_ := unset $annotations . }}{{ end -}}
{{- if not (empty $annotations) -}}
{{- toYaml $annotations -}}
{{- end -}}
{{- end -}}

{{/*
Shared ingress rules block for host(s) and path lists.
Call with dict "root" . "pathsTemplate" <name> "pathsMode" <string> (empty mode is fine).
Always passes dict "root" $root "mode" $pathsMode to the paths template.
*/}}
{{- define "eoapi.ingressRules" -}}
{{- $root := .root -}}
{{- $pathsTemplate := .pathsTemplate -}}
{{- $pathsMode := .pathsMode | default "" -}}
{{- $pathsCtx := dict "root" $root "mode" $pathsMode -}}
{{- if $root.Values.ingress.hosts }}
{{- range $root.Values.ingress.hosts }}
- host: {{ . }}
  http:
    paths:
      {{- include $pathsTemplate $pathsCtx | nindent 6 }}
{{- end }}
{{- else }}
- {{- if $root.Values.ingress.host }}
  host: {{ $root.Values.ingress.host }}
  {{- end }}
  http:
    paths:
      {{- include $pathsTemplate $pathsCtx | nindent 6 }}
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
Render a full Ingress manifest.
Call with dict:
  root, suffix, variant (main|auth-proxy|browser), pathsTemplate,
  pathsMode (optional), flags (required for main; caller-computed eoapi.ingressFlags)
*/}}
{{- define "eoapi.ingressManifest" -}}
{{- $root := .root -}}
{{- $suffix := .suffix -}}
{{- $variant := .variant -}}
{{- $owned := dict -}}
{{- $omit := list -}}
{{- $nginxRewriteKeys := list "nginx.ingress.kubernetes.io/rewrite-target" "nginx.ingress.kubernetes.io/use-regex" -}}
{{- if eq $variant "main" }}
  {{- $flags := .flags -}}
  {{- if and (eq $root.Values.ingress.className "nginx") $flags.nginxRewrite }}
    {{- $_ := set $owned "nginx.ingress.kubernetes.io/rewrite-target" "/$2" -}}
    {{- $_ := set $owned "nginx.ingress.kubernetes.io/use-regex" "true" -}}
  {{- end }}
  {{- if and (eq $root.Values.ingress.className "traefik") (not (empty $flags.stripPrefixes)) }}
    {{- $_ := set $owned "traefik.ingress.kubernetes.io/router.middlewares" (printf "%s-%s-strip-prefix-middleware@kubernetescrd" $root.Release.Namespace $root.Release.Name) -}}
  {{- end }}
{{- else if eq $variant "auth-proxy" }}
  {{- $omit = $nginxRewriteKeys -}}
{{- else if eq $variant "browser" }}
  {{- $omit = $nginxRewriteKeys -}}
  {{- if and (eq $root.Values.ingress.className "traefik") (include "eoapi.browserRedirectEnabled" $root | trim) }}
    {{- $_ := set $owned "traefik.ingress.kubernetes.io/router.middlewares" (printf "%s-%s-browser-redirect-middleware@kubernetescrd" $root.Release.Namespace $root.Release.Name) -}}
  {{- end }}
{{- end }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $root.Release.Name }}-{{ $suffix }}
  labels:
    app: {{ $root.Release.Name }}-{{ $suffix }}
  {{- with include "eoapi.ingressCommonAnnotations" (dict "root" $root "owned" $owned "omit" $omit) | trim }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  {{- with $root.Values.ingress.className }}
  ingressClassName: {{ . }}
  {{- end }}
  rules:
{{- include "eoapi.ingressRules" (dict "root" $root "pathsTemplate" .pathsTemplate "pathsMode" (.pathsMode | default "")) | nindent 4 }}
{{- with include "eoapi.ingressTls" $root | trim }}
{{ . | indent 2 }}
{{- end }}
{{- end -}}

{{/*
API ingress path rules. Call with dict "root" . "mode" "main"|"passthrough".
*/}}
{{- define "eoapi.apiIngressPaths" -}}
{{- $root := .root -}}
{{- $mode := .mode | default "main" -}}
{{- $isNginx := eq $root.Values.ingress.className "nginx" -}}
{{- range include "eoapi.enabledIngressServices" $root | fromJsonArray }}
{{- $include := false -}}
{{- if eq $mode "passthrough" }}
  {{- $include = .useAuthProxy -}}
{{- else -}}
  {{- $include = or (not $isNginx) (not .useAuthProxy) -}}
{{- end -}}
{{- if $include }}
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
{{- end }}
{{- if and (eq $mode "main") $root.Values.docServer.enabled }}
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
{{- trimSuffix "/" ((((.Values.browser).ingress).path) | default "/browser") | default "/" -}}
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
Browser ingress path rule. Call with dict "root" .
*/}}
{{- define "eoapi.browserIngressPaths" -}}
{{- $root := .root -}}
- pathType: Prefix
  path: {{ include "eoapi.browserIngressPath" $root }}
  backend:
    service:
      name: {{ $root.Release.Name }}-browser
      port:
        number: {{ (($root.Values.browser.service).port | default 8080) }}
{{- end -}}
