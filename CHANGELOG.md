# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.1]

### Added

- Added support for ConfigMap reference-based queryables configuration in addition to file-based queryables. Queryables can now be sourced from external ConfigMaps using `configMapRef`, from chart files using `file`, or a combination of both [#360](https://github.com/developmentseed/eoapi-k8s/pull/360)
- Added documentation for cloud-native bucket access [#364](https://github.com/developmentseed/eoapi-k8s/pull/364)
- Removed unused testing variable and unused deploy script [#369](https://github.com/developmentseed/eoapi-k8s/pull/369)

### Changed

- Unified scripts and removed Makefile, combined all into one CLI command `eoapi-cli` [#359](https://github.com/developmentseed/eoapi-k8s/pull/359)
- Added stac-auth-proxy for authentication and authorization on the STAC API [#358](https://github.com/developmentseed/eoapi-k8s/pull/358)
- Fixed call to run_queued_queries pgstac procedure call [#377](https://github.com/developmentseed/eoapi-k8s/pull/377)

### Dependencies

- Updated helm release grafana to 10.3.0 [#375](https://github.com/developmentseed/eoapi-k8s/pull/375)
- Updated helm release prometheus to 27.49.0 [#374](https://github.com/developmentseed/eoapi-k8s/pull/374)
- Updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.2 [#368](https://github.com/developmentseed/eoapi-k8s/pull/368)
- Updated actions/checkout action to v6 [#363](https://github.com/developmentseed/eoapi-k8s/pull/363)

## [0.8.0] - 2025-11-20

### Breaking changes

#### Refactored `eoapi-support` chart

This release refactored `eoapi-support` into the main `eoapi` chart. This includes all monitoring, observability and a lot of the metrics functionality. If you use any of this, please check on the new configuration structre and options as described in `docs/observability.md` and `docs/autoscaling.md`.

### Cleaned up to rely on default resource specification

Removed all default resource specifications from values.yaml and profile files. Users must now explicitly set resource limits/requests based on their infrastructure needs. This simplifies the chart and acknowledges that resource requirements vary greatly based on workload and infrastructure. If you were relying on the default resource specifications, add them to your values override file:

```yaml
stac:
  settings:
    resources:
      requests:
        cpu: "512m"
        memory: "1024Mi"
      limits:
        cpu: "1024m"
        memory: "2048Mi"
```

### Added

- Exposed PgSTAC configuration options in Helm chart values (`pgstacBootstrap.settings.pgstacSettings`). These are dynamically applied via templated SQL during bootstrap. [#340](https://github.com/developmentseed/eoapi-k8s/pull/340)
- Added `queue_timeout`, `use_queue`, and `update_collection_extent` settings for database performance tuning
  - Made existing context settings configurable (`context`, `context_estimated_count`, `context_estimated_cost`, `context_stats_ttl`)
  - Automatic queue processor CronJob created when `use_queue` is "true" (configurable schedule via `queueProcessor.schedule`)
  - Automatic extent updater CronJob created when `update_collection_extent` is "false" (configurable schedule via `extentUpdater.schedule`)
- Added ConfigMap checksum annotations to automatically restart pods when configuration changes [#344](https://github.com/developmentseed/eoapi-k8s/pull/344)
- Tests for autoscaling [#343](https://github.com/developmentseed/eoapi-k8s/pull/343)
- Added tests for observability stack [#342](https://github.com/developmentseed/eoapi-k8s/pull/342)
- Added validation to require `postgrescluster.enabled: false` when using external databases [#346](https://github.com/developmentseed/eoapi-k8s/pull/346)
- Added a production.yaml profile [#354](https://github.com/developmentseed/eoapi-k8s/pull/354)
- Added clarification about concurrency and db connection configuration. [#356](https://github.com/developmentseed/eoapi-k8s/pull/356)

### Changed

- Refactored eoapi-support into core eoapi chart [#262](https://github.com/developmentseed/eoapi-k8s/pull/262)
- Made integration tests fail properly [#341](https://github.com/developmentseed/eoapi-k8s/pull/341)
- Temporarily skipped VRT driver in GDALg to avoid https://github.com/OSGeo/gdal/issues/12645 [#243](https://github.com/developmentseed/eoapi-k8s/pull/243)
- Consistent naming of behavior field [#345](https://github.com/developmentseed/eoapi-k8s/pull/345)
- Made all python tests comply with mypy strict validation [#347](https://github.com/developmentseed/eoapi-k8s/pull/347)
- Improved documentation about access to grafana [#348](https://github.com/developmentseed/eoapi-k8s/pull/348)
- Reorganized local development values files into structured profiles directory [#351](https://github.com/developmentseed/eoapi-k8s/pull/351)
- Reorganized the helm chart templates files [#352](https://github.com/developmentseed/eoapi-k8s/pull/352)
- Removed all default resource specifications from values.yaml [#357](https://github.com/developmentseed/eoapi-k8s/pull/357)

### Dependencies

- Updated Python to 3.14.0 [#349](https://github.com/developmentseed/eoapi-k8s/pull/349)
- Updated actions/setup-python action to v6 [#350](https://github.com/developmentseed/eoapi-k8s/pull/350)
- Updated Helm release prometheus to 27.45.0 [#339](https://github.com/developmentseed/eoapi-k8s/pull/339)
- Updated Helm release knative-operator to v1.20.0 [#337](https://github.com/developmentseed/eoapi-k8s/pull/337)
- Updated helm release grafana to 10.1.5 [#361](https://github.com/developmentseed/eoapi-k8s/pull/361)
- Updated registry.k8s.io/ingress-nginx/kube-webhook-certgen Docker tag to v1.6.4 [#332](https://github.com/developmentseed/eoapi-k8s/pull/332)
- Updated actions/checkout action to v5 [#333](https://github.com/developmentseed/eoapi-k8s/pull/333)
- Updated actions/setup-node action to v6 [#334](https://github.com/developmentseed/eoapi-k8s/pull/334)
- Updated Node.js to 24.11.0 [#335](https://github.com/developmentseed/eoapi-k8s/pull/335)
- Updated tipg to v1.3.0 [#355](https://github.com/developmentseed/eoapi-k8s/pull/355)

## [0.7.13] - 2025-11-04

### Added

- Add queryables configuration support using pypgstac load-queryables [#323](https://github.com/developmentseed/eoapi-k8s/pull/323)
- Added local testing with k3s and minikube
- Unified local cluster management with `CLUSTER_TYPE` variable
- Improved CI and local debugging; added debug-deployment.sh script
- Added knative in CI to test eoapi-notifier.
- Restructured docs with flattened structure and added portable documentation generation

## [0.7.12] - 2025-10-17

- Bumped eoapi-notifier dependency version to 0.0.7

## [0.7.11] - 2025-10-17

- Bumped eoapi-notifier dependency version to 0.0.6

## [0.7.10] - 2025-10-06

### Fixed

- Fixed `stac.overrideRootPath` empty string handling for stac-auth-proxy integration - empty string now properly omits `--root-path` argument entirely [#307](https://github.com/developmentseed/eoapi-k8s/pull/307)
- Pin `metrics-server` to `bitnamilegacy` registry due to https://github.com/bitnami/charts/issues/35164 [#309](https://github.com/developmentseed/eoapi-k8s/pull/309)

## [0.7.9] - 2025-09-26

### Added

- Enforcement of `CHANGELOG.md` entries for PRs and Conventional Commits for PR titles [#288](https://github.com/developmentseed/eoapi-k8s/pull/288)
- Added code formatting and linting with pre-commit hooks [#283](https://github.com/developmentseed/eoapi-k8s/pull/283)
- Added values.schema.json validation [#296](https://github.com/developmentseed/eoapi-k8s/pull/296)
- Adjusted Renovate Configuration to fit conventional commits [#295](https://github.com/developmentseed/eoapi-k8s/pull/295)
- Notification triggers in database [#289](https://github.com/developmentseed/eoapi-k8s/pull/289)

## [0.7.8] - 2025-09-10

### Added

- Renovate for dependency management [#261](https://github.com/developmentseed/eoapi-k8s/pull/261)

### Changed

- Naming consistency [#259](https://github.com/developmentseed/eoapi-k8s/pull/259)
- Dependency version upgrades [#269](https://github.com/developmentseed/eoapi-k8s/pull/269)[#268](https://github.com/developmentseed/eoapi-k8s/pull/268)[#266](https://github.com/developmentseed/eoapi-k8s/pull/266)[#271](https://github.com/developmentseed/eoapi-k8s/pull/271)[#267](https://github.com/developmentseed/eoapi-k8s/pull/267)[#277](https://github.com/developmentseed/eoapi-k8s/pull/277)[#278](https://github.com/developmentseed/eoapi-k8s/pull/278)[#276](https://github.com/developmentseed/eoapi-k8s/pull/276)[#282](https://github.com/developmentseed/eoapi-k8s/pull/282)[#281](https://github.com/developmentseed/eoapi-k8s/pull/281)[#273](https://github.com/developmentseed/eoapi-k8s/pull/273)[#280](https://github.com/developmentseed/eoapi-k8s/pull/280)[#279](https://github.com/developmentseed/eoapi-k8s/pull/279)[#272](https://github.com/developmentseed/eoapi-k8s/pull/272)
- Docs refreshed [#260](https://github.com/developmentseed/eoapi-k8s/pull/260)[#285](https://github.com/developmentseed/eoapi-k8s/pull/285)

### Fixed

- `multidim`, `raster`, `stac`, and `vector` now allow annotations [#286](https://github.com/developmentseed/eoapi-k8s/pull/286)

## [0.7.7] - 2025-09-05

### Fixed

- Order of hook execution [#257](https://github.com/developmentseed/eoapi-k8s/pull/257)

## [0.7.6] - 2025-09-03

### Added

- Added support for multiple hosts in ingress configuration via `ingress.hosts` array [#248](https://github.com/developmentseed/eoapi-k8s/pull/248)
- Notes on M1 flavour Macs and pulling images [#250](https://github.com/developmentseed/eoapi-k8s/pull/250)
- Ability to apply annotations to STAC Browser service [#255](https://github.com/developmentseed/eoapi-k8s/pull/255)

### Fixed

- Issues regarding timeouts waiting for postgres initialisation [#251](https://github.com/developmentseed/eoapi-k8s/pull/251) [#252](https://github.com/developmentseed/eoapi-k8s/pull/252)
- Aligned STAC Browser metadata to other services [#255](https://github.com/developmentseed/eoapi-k8s/pull/255)

## [0.7.5] - 2025-07-11

### Changed

- Added option to override root-paths of API services [#245](https://github.com/developmentseed/eoapi-k8s/pull/245)

## [0.7.4] - 2025-06-30

### Changed

- Added support for configurable API paths [#237](https://github.com/developmentseed/eoapi-k8s/pull/237)
- Clarified database initialization permissions [#240](https://github.com/developmentseed/eoapi-k8s/pull/240)

## [0.7.3] - 2025-05-27

### Changed

- Add CREATEROLE privilege to pgstac user [#236](https://github.com/developmentseed/eoapi-k8s/pull/236)

## [v0.7.2] - 2025-05-27

### Changed

Made 0.7.0 db upgrade run in ArgoCD.

## [v0.7.1] - 2025-05-16

### Breaking Changes
- Removed hard-coded cert-manager configuration from ingress template [#227](https://github.com/developmentseed/eoapi-k8s/pull/227)
- Removed `pathType` and `pathSuffix` configurations in favor of controller-specific defaults [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)

### Added
- Added upgrade job to handle database permissions for migrations from pre-0.7.0 versions [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)
- Added separate ingress configuration for STAC browser [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)
- Added support for custom cluster naming via `postgrescluster.name` [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)

### Changed
- Improved Nginx and Traefik support with controller-specific rewrites [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)
- Increased bootstrap job retry limit to 3 attempts [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)
- Enhanced secret handling with custom PostgreSQL cluster names [#228](https://github.com/developmentseed/eoapi-k8s/pull/228)
- Simplified TLS configuration to allow user-controlled certificate management [#227](https://github.com/developmentseed/eoapi-k8s/pull/227)
- Updated documentation with comprehensive cert-manager setup guide [#227](https://github.com/developmentseed/eoapi-k8s/pull/227)

## [v0.7.0] - 2025-04-30

### Breaking Changes
- New unified ingress configuration requires migration from previous ingress setup [#219](https://github.com/developmentseed/eoapi-k8s/pull/219)
- Refactored PostgreSQL configuration with removal of deprecated database setup [#215](https://github.com/developmentseed/eoapi-k8s/pull/215)
- Major architectural changes with service-specific templates [#220](https://github.com/developmentseed/eoapi-k8s/pull/220)

### Added
- STAC Browser integration [#168](https://github.com/developmentseed/eoapi-k8s/pull/168)
- Azure secret vault integration for pg-stac secrets [#187](https://github.com/developmentseed/eoapi-k8s/pull/187)
- Support for both NGINX and Traefik ingress controllers [#219](https://github.com/developmentseed/eoapi-k8s/pull/219)
- ArtifactHub.io Integration [#216](https://github.com/developmentseed/eoapi-k8s/pull/216)

### Changed
- Refactored pgstacbootstrap job and ConfigMaps to use Helm hooks for execution order [#207](https://github.com/developmentseed/eoapi-k8s/pull/207)
- Simplified PgSTAC Bootstrap Process [#208](https://github.com/developmentseed/eoapi-k8s/pull/208)
- Upgraded stac-fastapi-pgstac to v5.0.2 [#204](https://github.com/developmentseed/eoapi-k8s/pull/204)
### Fixed
- Fixed ArtifactHub.io Integration (Issue #16) [#216](https://github.com/developmentseed/eoapi-k8s/pull/216)

## [v0.6.0] - 2025-04-03

### Breaking Changes
- Database backups are now disabled by default. To enable them, set `backupsEnabled: true` in your values.yaml.

### Added
- Added initContainers to wait for db and its bootstrap [#194](https://github.com/developmentseed/eoapi-k8s/pull/194)
- Made all eoAPI services wait for db bootstrap [#197](https://github.com/developmentseed/eoapi-k8s/pull/197)

### Changed
- Updated GCP Setup instructions [#188](https://github.com/developmentseed/eoapi-k8s/pull/188)
- Removed GCP CI deployment tests [#193](https://github.com/developmentseed/eoapi-k8s/pull/193)
- Upgraded PGO to 5.7.0; Added option to disable backups [#191](https://github.com/developmentseed/eoapi-k8s/pull/191)
- Upgraded dependencies [#196](https://github.com/developmentseed/eoapi-k8s/pull/196)
- Upgraded to latest stac-fastapi-pgstac [#195](https://github.com/developmentseed/eoapi-k8s/pull/195)
- Upgraded tipg to 1.0.1 and titiler-pgstac to 1.7.1 [#199](https://github.com/developmentseed/eoapi-k8s/pull/199)

### Fixed
- Fixed multidim entrypoint [#192](https://github.com/developmentseed/eoapi-k8s/pull/192)
- Fixed unsupported regex in ingress-nginx config [#189](https://github.com/developmentseed/eoapi-k8s/pull/189)
- Reduced errors about too many db connections [#198](https://github.com/developmentseed/eoapi-k8s/pull/198)

## [v0.5.3] - 2025-03-10

### Added
- Allowed Repeated Helm Deployments [#169](https://github.com/developmentseed/eoapi-k8s/pull/169)
- Created health documentation [#171](https://github.com/developmentseed/eoapi-k8s/pull/171)
- Introduced a list to avoid hardcoding of api service names [#180](https://github.com/developmentseed/eoapi-k8s/pull/180)
- Added multidim api service [#182](https://github.com/developmentseed/eoapi-k8s/pull/182)
- Added tolerations and affinity support [#176](https://github.com/developmentseed/eoapi-k8s/pull/176)
- Allowed setting annotations for deployments [#177](https://github.com/developmentseed/eoapi-k8s/pull/177)

### Changed
- Used template functions to quote env vars [#170](https://github.com/developmentseed/eoapi-k8s/pull/170)
- Improved probe setup [#183](https://github.com/developmentseed/eoapi-k8s/pull/183)

### Fixed
- Fixed helm template error if docServer settings is not defined [#178](https://github.com/developmentseed/eoapi-k8s/pull/178)

## [v0.5.2] - 2024-12-05

### Added
- Allowed additional secrets to set environment variables [#167](https://github.com/developmentseed/eoapi-k8s/pull/167)

## [v0.5.1] - 2024-11-22

### Added
- Added ingest.sh script [#164](https://github.com/developmentseed/eoapi-k8s/pull/164)

### Fixed
- Added passthrough for ca bundle secret into metrics server [#165](https://github.com/developmentseed/eoapi-k8s/pull/165)

## [v0.5.0] - 2024-11-01

### Added
- Documented choice of postgres operator [#160](https://github.com/developmentseed/eoapi-k8s/pull/160)
- Added a basic makefile [#162](https://github.com/developmentseed/eoapi-k8s/pull/162)
- Added icon [#163](https://github.com/developmentseed/eoapi-k8s/pull/163)

### Changed
- Updated titiler-pgstac version [#157](https://github.com/developmentseed/eoapi-k8s/pull/157)
- Bumped eoapi chart and app versions [#158](https://github.com/developmentseed/eoapi-k8s/pull/158)

## [v0.4.18] - 2024-09-25

### Fixed
- Removed VSIL allowed extensions list [#152](https://github.com/developmentseed/eoapi-k8s/pull/152)

### Changed
- Bumped eoapi chart version [#153](https://github.com/developmentseed/eoapi-k8s/pull/153)

## [v0.4.17] - 2024-09-24

### Changed
- Changed Dependency Order in Support Chart [#150](https://github.com/developmentseed/eoapi-k8s/pull/150)

## [v0.4.16] - 2024-09-20

### Changed
- Upgraded with postgres cluster 5.5.3 [#149](https://github.com/developmentseed/eoapi-k8s/pull/149)

## [v0.4.15] - 2024-09-20

### Changed
- Postgrescluster chart upgrade [#148](https://github.com/developmentseed/eoapi-k8s/pull/148)

## [v0.4.14] - 2024-09-20

### Added
- Added NFS Option to PGBackRest [#147](https://github.com/developmentseed/eoapi-k8s/pull/147)

## [v0.4.13] - 2024-09-09

### Fixed
- Added back postgrescluster dependency to main eoapi chart [#145](https://github.com/developmentseed/eoapi-k8s/pull/145)

## [v0.4.10] - 2024-09-09

### Changed
- Moved postgresql cluster file:// dependency to first-level chart dependency [#141](https://github.com/developmentseed/eoapi-k8s/pull/141)

## [v0.4.9] - 2024-09-04

### Fixed
- Fixed horizontal pod autoscaling rules [#140](https://github.com/developmentseed/eoapi-k8s/pull/140)

### Changed
- Documentation updates [#139](https://github.com/developmentseed/eoapi-k8s/pull/139)

## [v0.4.8] - 2024-09-03

### Changed
- Enabled vector by default again [#138](https://github.com/developmentseed/eoapi-k8s/pull/138)

## [v0.4.7] - 2024-09-03

### Added
- Support and Autoscaling Additions [#135](https://github.com/developmentseed/eoapi-k8s/pull/135)

## [v0.4.6] - 2024-07-17

### Changed
- Bump chart patch versions [#131](https://github.com/developmentseed/eoapi-k8s/pull/131)

## [v0.4.2] - 2024-07-11

### Fixed
- Pinned pypgstac versions [#126](https://github.com/developmentseed/eoapi-k8s/pull/126)

## [v0.4.1] - 2024-07-10

### Added
- Added Release Documentation and Cleanup [#117](https://github.com/developmentseed/eoapi-k8s/pull/117)

## [v0.4.0] - 2024-07-09

### Added
- Started EKS IAC with Docs Walkthrough from Notes [#12](https://github.com/developmentseed/eoapi-k8s/pull/12)
- Added Single Nginx Ingress and NLB with path rewrites [#11](https://github.com/developmentseed/eoapi-k8s/pull/11)
- Added Unit tests [#14](https://github.com/developmentseed/eoapi-k8s/pull/14)
- Documented GKE k8s cluster setup [#27](https://github.com/developmentseed/eoapi-k8s/pull/27)
- Generalized commands and added livenessProbe [#35](https://github.com/developmentseed/eoapi-k8s/pull/35)
- Added HPA (CPU) draft before locust/artillery [#51](https://github.com/developmentseed/eoapi-k8s/pull/51)
- Added Autoscaling by request rate [#53](https://github.com/developmentseed/eoapi-k8s/pull/53)
- Added Support for specifying host and getting certs from cert manager [#60](https://github.com/developmentseed/eoapi-k8s/pull/60)
- Added Configuration for EKS autoscaler [#59](https://github.com/developmentseed/eoapi-k8s/pull/59)
- Added PGO by default [#84](https://github.com/developmentseed/eoapi-k8s/pull/84)
- Added fixtures [#9](https://github.com/developmentseed/eoapi-k8s/pull/9)
- Allowed custom annotations [#66](https://github.com/developmentseed/eoapi-k8s/pull/66)
- Tested autoscaling in EKS [#55](https://github.com/developmentseed/eoapi-k8s/pull/55)

### Changed
- Set default gitSha and inserted main gitSha for distributed helm-chart [#21](https://github.com/developmentseed/eoapi-k8s/pull/21)
- Renamed repository [#23](https://github.com/developmentseed/eoapi-k8s/pull/23)
- Added more explicit nginx documentation [#24](https://github.com/developmentseed/eoapi-k8s/pull/24)
- Updated Root path HTML [#25](https://github.com/developmentseed/eoapi-k8s/pull/25)
- Made GKE related changes [#37](https://github.com/developmentseed/eoapi-k8s/pull/37)
- Updated Release name for parallel CI tests [#43](https://github.com/developmentseed/eoapi-k8s/pull/43)
- Updated API version for release [#49](https://github.com/developmentseed/eoapi-k8s/pull/49)
- Upgraded pgstac, titiler-pgstac and tipg versions [#67](https://github.com/developmentseed/eoapi-k8s/pull/67)

### Fixed
- Fixed Database resources to set limits and requests [#46](https://github.com/developmentseed/eoapi-k8s/pull/46)
- Fixed Integration tests with image upgrade [#68](https://github.com/developmentseed/eoapi-k8s/pull/68)
- Avoided immediate scaleup if autoscale is enabled [#52](https://github.com/developmentseed/eoapi-k8s/pull/52)
