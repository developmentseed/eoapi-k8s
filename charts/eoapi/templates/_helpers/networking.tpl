{{/*
Return true when API services should enable proxy header and root-path flags.
Only NGINX and Traefik ingress controllers are supported.
*/}}
{{- define "eoapi.ingressUsesProxyHeaders" -}}
{{- $class := .Values.ingress.className -}}
{{- if and $class (or (eq $class "nginx") (eq $class "traefik")) -}}true{{- end -}}
{{- end -}}

{{/*
Per-service metadata for unified ingress routing (not the service list itself).
*/}}
{{- define "eoapi.ingressServiceMetadata" -}}
{{- dict
  "stac" (dict "usesAuthProxy" true)
  "browser" (dict "defaultPath" "/browser" "hasOwnPort" true "skipStripPrefix" true "browser" true)
  "mockOidcServer" (dict "actualName" "mock-oidc-server" "hasOwnPort" true "valuesPath" (list "testing" "mockOidcServer"))
| toJson -}}
{{- end -}}

{{/*
Unified ingress service metadata. API services come from values.apiServices; extras are appended.
*/}}
{{- define "eoapi.ingressServiceEntries" -}}
{{- $root := . -}}
{{- $meta := include "eoapi.ingressServiceMetadata" $root | fromJson -}}
{{- $entries := list -}}
{{- range $root.Values.apiServices }}
  {{- $entry := dict "key" . -}}
  {{- $svcMeta := index $meta . | default dict -}}
  {{- range $k, $v := $svcMeta }}
    {{- $_ := set $entry $k $v }}
  {{- end }}
  {{- $entries = append $entries $entry -}}
{{- end }}
{{- range $extraKey, $extraMeta := dict
  "browser" (index $meta "browser")
  "mockOidcServer" (index $meta "mockOidcServer")
}}
  {{- $entry := dict "key" $extraKey -}}
  {{- range $k, $v := $extraMeta }}
    {{- $_ := set $entry $k $v }}
  {{- end }}
  {{- $entries = append $entries $entry -}}
{{- end }}
{{- toJson $entries -}}
{{- end -}}

{{/*
Resolve a service values object from an ingress service entry as JSON.
*/}}
{{- define "eoapi.ingressServiceFromEntry" -}}
{{- $root := .root -}}
{{- $entry := .entry -}}
{{- $service := index $root.Values $entry.key -}}
{{- if $entry.valuesPath }}
  {{- $service = $root.Values -}}
  {{- range $entry.valuesPath }}
    {{- $service = index $service . -}}
  {{- end }}
{{- end }}
{{- if $service }}{{ toJson $service }}{{ end -}}
{{- end -}}

{{/*
Effective ingress path for a service, honoring overrideRootPath when set to a non-empty value.
*/}}
{{- define "eoapi.serviceIngressPath" -}}
{{- $service := .service -}}
{{- $defaultPath := .defaultPath | default "" -}}
{{- $path := $service.ingress.path | default $defaultPath -}}
{{- if and $service.overrideRootPath (ne $service.overrideRootPath "") -}}
{{- $path = $service.overrideRootPath -}}
{{- end -}}
{{- $path -}}
{{- end -}}

{{/*
Return JSON array of fully resolved ingress routes for enabled services and doc server.
*/}}
{{- define "eoapi.ingressRoutes" -}}
{{- $root := . -}}
{{- $routes := list -}}
{{- range include "eoapi.ingressServiceEntries" $root | fromJsonArray }}
  {{- $entry := . -}}
  {{- $service := include "eoapi.ingressServiceFromEntry" (dict "root" $root "entry" $entry) | fromJson -}}
  {{- if and $service $service.enabled (or (not $service.ingress) $service.ingress.enabled) }}
    {{- $useAuthProxy := and $entry.usesAuthProxy (index $root.Values "stac-auth-proxy" "enabled") -}}
    {{- $path := include "eoapi.serviceIngressPath" (dict "service" $service "defaultPath" $entry.defaultPath) | trim -}}
    {{- $stripPath := and (ne $path "/") (not (or $entry.skipStripPrefix $useAuthProxy)) -}}
    {{- $serviceName := $entry.actualName | default $entry.key -}}
    {{- $port := $root.Values.service.port -}}
    {{- if $entry.hasOwnPort }}
      {{- if $service.service }}
        {{- $port = $service.service.port | default 8080 }}
      {{- else }}
        {{- $port = 8080 }}
      {{- end }}
    {{- end }}
    {{- $routes = append $routes (dict
      "serviceKey" $entry.key
      "path" $path
      "serviceName" $serviceName
      "port" $port
      "stripPath" $stripPath
      "useAuthProxy" $useAuthProxy
      "preservePrefix" (eq $path "/")
      "nginxSeparateIngress" (or $entry.skipStripPrefix $useAuthProxy)
      "browser" ($entry.browser | default false)
    ) }}
  {{- end }}
{{- end }}
{{- if $root.Values.docServer.enabled }}
  {{- $routes = append $routes (dict
    "serviceKey" "docServer"
    "path" (include "eoapi.docServerIngressPath" $root)
    "serviceName" "doc-server"
    "port" 80
    "stripPath" false
    "useAuthProxy" false
    "preservePrefix" true
    "nginxSeparateIngress" false
    "browser" false
    "docServer" true
  ) }}
{{- end }}
{{- toJson $routes -}}
{{- end -}}

{{/*
Return JSON array of path prefixes that require strip-prefix / NGINX rewrite handling.
*/}}
{{- define "eoapi.stripPrefixes" -}}
{{- $prefixes := list -}}
{{- range include "eoapi.ingressRoutes" . | fromJsonArray }}
  {{- if .stripPath }}
    {{- $prefixes = append $prefixes .path }}
  {{- end }}
{{- end -}}
{{- toJson $prefixes -}}
{{- end -}}

{{/*
Return true when NGINX main ingress needs rewrite-target for API path stripping.
*/}}
{{- define "eoapi.nginxNeedsRewriteTarget" -}}
{{- if ne .Values.ingress.className "nginx" -}}
{{- else if include "eoapi.stripPrefixes" . | fromJsonArray -}}
true
{{- end -}}
{{- end -}}

{{/*
Normalized doc-server ingress path from ingress.rootPath.
*/}}
{{- define "eoapi.docServerIngressPath" -}}
{{- $rootPath := trimPrefix "/" (.Values.ingress.rootPath | default "") -}}
{{- if $rootPath -}}
{{- printf "/%s" $rootPath -}}
{{- else -}}
/
{{- end -}}
{{- end -}}

{{/*
Return true when a route should render for the given ingress path filter.
Filters: main, preserve, browser, browserRedirect, stacAuth
*/}}
{{- define "eoapi.ingressRouteMatchesFilter" -}}
{{- $route := .route -}}
{{- $filter := .filter -}}
{{- $isNginx := .isNginx -}}
{{- $match := false -}}
{{- if eq $filter "main" -}}
  {{- if not $isNginx -}}
    {{- $match = true -}}
  {{- else if and (not $route.docServer) (not $route.preservePrefix) (not $route.nginxSeparateIngress) -}}
    {{- $match = true -}}
  {{- end -}}
{{- else if eq $filter "preserve" -}}
  {{- if and $isNginx (or $route.docServer (and (not $route.nginxSeparateIngress) $route.preservePrefix)) -}}
    {{- $match = true -}}
  {{- end -}}
{{- else if eq $filter "browser" -}}
  {{- if and $isNginx $route.browser -}}
    {{- $match = true -}}
  {{- end -}}
{{- else if eq $filter "browserRedirect" -}}
  {{- if and $isNginx $route.browser (ne $route.path "/") -}}
    {{- $match = true -}}
  {{- end -}}
{{- else if eq $filter "stacAuth" -}}
  {{- if and $isNginx $route.useAuthProxy -}}
    {{- $match = true -}}
  {{- end -}}
{{- end -}}
{{- if $match -}}true{{- end -}}
{{- end -}}

{{/*
Parameterized ingress path renderer. Filter: main, preserve, browser, browserRedirect, stacAuth
*/}}
{{- define "eoapi.renderIngressPaths" -}}
{{- $root := .root -}}
{{- $filter := .filter -}}
{{- $isNginx := eq $root.Values.ingress.className "nginx" -}}
{{- range include "eoapi.ingressRoutes" $root | fromJsonArray }}
  {{- $route := . -}}
  {{- if include "eoapi.ingressRouteMatchesFilter" (dict "route" $route "filter" $filter "isNginx" $isNginx) | trim }}
{{- if eq $filter "browser" }}
- pathType: Prefix
  path: {{ printf "%s/" $route.path }}
{{- else if eq $filter "browserRedirect" }}
- pathType: Exact
  path: {{ $route.path }}
{{- else if eq $filter "preserve" }}
- pathType: Prefix
  path: {{ $route.path }}
{{- else if eq $filter "stacAuth" }}
- pathType: Prefix
  path: {{ $route.path }}
{{- else }}
- pathType: {{ if and $isNginx $route.stripPath }}ImplementationSpecific{{ else }}Prefix{{ end }}
  path: {{ $route.path }}{{ if and $isNginx $route.stripPath }}(/|$)(.*){{ end }}
{{- end }}
  backend:
    service:
      {{- if $route.useAuthProxy }}
      name: {{ $root.Release.Name }}-stac-auth-proxy
      {{- else }}
      name: {{ $root.Release.Name }}-{{ $route.serviceName }}
      {{- end }}
      port:
        number: {{ $route.port }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Generate ingress path rules for enabled services on the main ingress.
On NGINX, browser, auth-proxy, and prefix-preserving routes use separate ingresses.
*/}}
{{- define "eoapi.ingressPaths" -}}
{{- include "eoapi.renderIngressPaths" (dict "root" . "filter" "main") -}}
{{- end -}}

{{/*
Generate prefix-preserving ingress path rules for NGINX root-path and doc-server routes.
*/}}
{{- define "eoapi.preservePrefixIngressPaths" -}}
{{- include "eoapi.renderIngressPaths" (dict "root" . "filter" "preserve") -}}
{{- end -}}

{{/*
Generate browser-only ingress path rules (NGINX separate ingress).
*/}}
{{- define "eoapi.browserIngressPaths" -}}
{{- include "eoapi.renderIngressPaths" (dict "root" . "filter" "browser") -}}
{{- end -}}

{{/*
Generate stac-auth-proxy ingress path rules (NGINX separate ingress without rewrite-target).
*/}}
{{- define "eoapi.stacAuthIngressPaths" -}}
{{- include "eoapi.renderIngressPaths" (dict "root" . "filter" "stacAuth") -}}
{{- end -}}

{{/*
Generate exact-match browser redirect path rules (NGINX bare-path redirect ingress).
*/}}
{{- define "eoapi.browserRedirectIngressPaths" -}}
{{- include "eoapi.renderIngressPaths" (dict "root" . "filter" "browserRedirect") -}}
{{- end -}}

{{/*
Normalized ingress host list: ingress.hosts when set, else [ingress.host], else [].
*/}}
{{- define "eoapi.ingressHostList" -}}
{{- if .Values.ingress.hosts -}}
{{- .Values.ingress.hosts | toJson -}}
{{- else if .Values.ingress.host -}}
{{- list .Values.ingress.host | toJson -}}
{{- else -}}
{{- list | toJson -}}
{{- end -}}
{{- end -}}

{{/*
Shared ingress rules for single-host or multi-host configurations.
*/}}
{{- define "eoapi.ingressRules" -}}
{{- $root := .root -}}
{{- $pathsTpl := .pathsTpl -}}
{{- $hosts := include "eoapi.ingressHostList" $root | fromJsonArray -}}
{{- if $hosts }}
{{- range $hosts }}
- host: {{ . }}
  http:
    paths:
      {{- include $pathsTpl $root | nindent 6 }}
{{- end }}
{{- else }}
-
  http:
    paths:
      {{- include $pathsTpl $root | nindent 6 }}
{{- end }}
{{- end -}}

{{/*
Shared TLS configuration for ingress resources.
*/}}
{{- define "eoapi.ingressTLS" -}}
{{- $hosts := include "eoapi.ingressHostList" . | fromJsonArray -}}
{{- if and .Values.ingress.tls.enabled $hosts }}
tls:
  - hosts:
      {{- range $hosts }}
      - {{ . }}
      {{- end }}
    secretName: {{ .Values.ingress.tls.secretName }}
{{- end }}
{{- end -}}

{{/*
Return the configured browser ingress path without trailing slash, or empty when unavailable.
*/}}
{{- define "eoapi.browserIngressPath" -}}
{{- range include "eoapi.ingressRoutes" . | fromJsonArray }}
  {{- if .browser -}}
    {{- trimSuffix "/" .path -}}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
NGINX annotation keys unsafe on prefix-preserving ingress resources.
*/}}
{{- define "eoapi.ingressUnsafeAnnotationKeys" -}}
{{- toJson (list
  "nginx.ingress.kubernetes.io/rewrite-target"
  "nginx.ingress.kubernetes.io/use-regex"
  "nginx.ingress.kubernetes.io/permanent-redirect"
  "nginx.ingress.kubernetes.io/permanent-redirect-code"
  "nginx.ingress.kubernetes.io/server-snippet"
  "nginx.ingress.kubernetes.io/configuration-snippet"
) -}}
{{- end -}}

{{/*
Compatibility-filtered subset of ingress.annotations for separate NGINX ingress resources.
*/}}
{{- define "eoapi.ingressCompatibilityFilteredAnnotations" -}}
{{- $filtered := dict -}}
{{- $blocked := include "eoapi.ingressUnsafeAnnotationKeys" . | fromJsonArray -}}
{{- range $key, $value := (.Values.ingress.annotations | default dict) }}
  {{- if not (has $key $blocked) }}
    {{- $_ := set $filtered $key $value }}
  {{- end }}
{{- end }}
{{- $filtered | toJson -}}
{{- end -}}

{{/*
Merge explicit per-resource annotations over compatibility-filtered ingress.annotations.
*/}}
{{- define "eoapi.ingressMergedAnnotations" -}}
{{- $root := .root -}}
{{- $explicit := index $root.Values.ingress .explicitKey | default dict -}}
{{- $merged := include "eoapi.ingressCompatibilityFilteredAnnotations" $root | fromJson -}}
{{- range $key, $value := $explicit }}
  {{- $_ := set $merged $key $value }}
{{- end }}
{{- if $merged }}
{{- toYaml $merged -}}
{{- end -}}
{{- end -}}

{{/*
Annotations for NGINX preserve-prefix ingress resources.
*/}}
{{- define "eoapi.preservePrefixIngressAnnotations" -}}
{{- include "eoapi.ingressMergedAnnotations" (dict "root" . "explicitKey" "preservePrefixAnnotations") -}}
{{- end -}}

{{/*
Annotations for NGINX browser ingress resources.
*/}}
{{- define "eoapi.browserIngressAnnotations" -}}
{{- include "eoapi.ingressMergedAnnotations" (dict "root" . "explicitKey" "browserAnnotations") -}}
{{- end -}}

{{/*
Annotations for NGINX stac-auth ingress resources.
*/}}
{{- define "eoapi.stacAuthIngressAnnotations" -}}
{{- include "eoapi.ingressMergedAnnotations" (dict "root" . "explicitKey" "stacAuthAnnotations") -}}
{{- end -}}

{{/*
Return trailing-slash redirect target for bare browser path, or empty when unavailable.
*/}}
{{- define "eoapi.browserRedirectTarget" -}}
{{- $path := include "eoapi.browserIngressPath" . | trim -}}
{{- if and $path (ne $path "/") -}}
{{- printf "%s/" $path -}}
{{- end -}}
{{- end -}}

{{/*
Return the primary ingress host: ingress.host, or the first entry in ingress.hosts.
*/}}
{{- define "eoapi.ingressPrimaryHost" -}}
{{- $hosts := include "eoapi.ingressHostList" . | fromJsonArray -}}
{{- if $hosts -}}
{{- index $hosts 0 -}}
{{- end -}}
{{- end -}}

{{/*
Return http or https based on ingress TLS configuration.
*/}}
{{- define "eoapi.ingressScheme" -}}
{{- if .Values.ingress.tls.enabled -}}https{{- else -}}http{{- end -}}
{{- end -}}

{{/*
Default STAC catalog URL for the browser when browser.catalogUrl is unset.
*/}}
{{- define "eoapi.browserCatalogUrl" -}}
{{- printf "%s://%s%s" (include "eoapi.ingressScheme" .) (include "eoapi.ingressPrimaryHost" .) .Values.stac.ingress.path -}}
{{- end -}}

{{/*
OAuth redirect URI for the browser when browser.authConfig is unset.
*/}}
{{- define "eoapi.browserRedirectUri" -}}
{{- $path := .Values.browser.ingress.path | default "/browser" | trimSuffix "/" -}}
{{- printf "%s://%s%s/auth" (include "eoapi.ingressScheme" .) (include "eoapi.ingressPrimaryHost" .) $path -}}
{{- end -}}

{{/*
Comma-separated Traefik middleware references for the unified ingress router.
*/}}
{{- define "eoapi.ingressTraefikMiddlewares" -}}
{{- $root := . -}}
{{- $mwPrefix := printf "%s-%s" $root.Release.Namespace $root.Release.Name -}}
{{- $middlewares := list -}}
{{- if include "eoapi.stripPrefixes" $root | fromJsonArray }}
{{- $middlewares = append $middlewares (printf "%s-strip-prefix-middleware@kubernetescrd" $mwPrefix) -}}
{{- end }}
{{- range include "eoapi.ingressRoutes" $root | fromJsonArray }}
{{- if .browser }}
{{- $middlewares = append $middlewares (printf "%s-browser-redirect-middleware@kubernetescrd" $mwPrefix) -}}
{{- end }}
{{- end }}
{{- join "," $middlewares -}}
{{- end -}}
