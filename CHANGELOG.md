# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added


### Changed

* Refactor pgstacbootstrap job and ConfigMaps to use Helm hooks for execution order [#207](https://github.com/developmentseed/eoapi-k8s/pull/207)
* Simplify PgSTAC Bootstrap Process [#208](https://github.com/developmentseed/eoapi-k8s/pull/208)
* Upgrade stac-fastapi-pgstac to v5.0.2 [#204](https://github.com/developmentseed/eoapi-k8s/pull/204)

### Deprecated

### Removed

### Fixed

### Security

## [v0.6.0] - 2025-04-03

### Breaking Changes
- Database backups are now disabled by default. To enable them, set `backupsEnabled: true` in your values.yaml.

### Added
- Add initContainers to wait for db and its bootstrap [#194](https://github.com/developmentseed/eoapi-k8s/pull/194)
- Let all eoAPI services wait for db bootstrap [#197](https://github.com/developmentseed/eoapi-k8s/pull/197)

### Changed
- Update GCP Setup instructions [#188](https://github.com/developmentseed/eoapi-k8s/pull/188)
- Remove GCP CI deployment tests [#193](https://github.com/developmentseed/eoapi-k8s/pull/193)
- Upgrade PGO to 5.7.0; Add option to disable backups [#191](https://github.com/developmentseed/eoapi-k8s/pull/191)
- Upgrade dependencies [#196](https://github.com/developmentseed/eoapi-k8s/pull/196)
- Upgrade to latest stac-fastapi-pgstac [#195](https://github.com/developmentseed/eoapi-k8s/pull/195)
- Upgrade tipg to 1.0.1 and titiler-pgstac to 1.7.1 [#199](https://github.com/developmentseed/eoapi-k8s/pull/199)

### Fixed
- Fix multidim entrypoint [#192](https://github.com/developmentseed/eoapi-k8s/pull/192)
- Fix unsupported regex in ingress-nginx config [#189](https://github.com/developmentseed/eoapi-k8s/pull/189)
- Reduce errors about too many db connections [#198](https://github.com/developmentseed/eoapi-k8s/pull/198)

## [v0.5.3] - 2025-03-10

### Added
- Allow Repeated Helm Deployments [#169](https://github.com/developmentseed/eoapi-k8s/pull/169)
- Create health documentation [#171](https://github.com/developmentseed/eoapi-k8s/pull/171)
- Introduce a list to avoid hardcoding of api service names [#180](https://github.com/developmentseed/eoapi-k8s/pull/180)
- Add multidim api service [#182](https://github.com/developmentseed/eoapi-k8s/pull/182)
- Tolerations and affinity support [#176](https://github.com/developmentseed/eoapi-k8s/pull/176)
- Allow setting annotations for deployments [#177](https://github.com/developmentseed/eoapi-k8s/pull/177)

### Changed
- Use template functions to quote env vars [#170](https://github.com/developmentseed/eoapi-k8s/pull/170)
- Improve probe setup [#183](https://github.com/developmentseed/eoapi-k8s/pull/183)

### Fixed
- Fix helm template error if docServer settings is not defined [#178](https://github.com/developmentseed/eoapi-k8s/pull/178)

## [v0.5.2] - 2024-12-05

### Added
- Allow additional secrets to set environment variables [#167](https://github.com/developmentseed/eoapi-k8s/pull/167)

## [v0.5.1] - 2024-11-22

### Added
- Add ingest.sh script [#164](https://github.com/developmentseed/eoapi-k8s/pull/164)

### Fixed
- Add passthrough for ca bundle secret into metrics server [#165](https://github.com/developmentseed/eoapi-k8s/pull/165)

## [v0.5.0] - 2024-11-01

### Added
- Document choice of postgres operator [#160](https://github.com/developmentseed/eoapi-k8s/pull/160)
- Add a basic makefile [#162](https://github.com/developmentseed/eoapi-k8s/pull/162)
- Add icon [#163](https://github.com/developmentseed/eoapi-k8s/pull/163)

### Changed
- Update titiler-pgstac version [#157](https://github.com/developmentseed/eoapi-k8s/pull/157)
- Bump eoapi chart and app versions [#158](https://github.com/developmentseed/eoapi-k8s/pull/158)

## [v0.4.18] - 2024-09-25

### Fixed
- Remove VSIL allowed extensions list [#152](https://github.com/developmentseed/eoapi-k8s/pull/152)

### Changed
- Bump eoapi chart version [#153](https://github.com/developmentseed/eoapi-k8s/pull/153)

## [v0.4.17] - 2024-09-24

### Changed
- Change Dependency Order in Support Chart [#150](https://github.com/developmentseed/eoapi-k8s/pull/150)

## [v0.4.16] - 2024-09-20

### Changed
- Upgrade with postgres cluster 5.5.3 [#149](https://github.com/developmentseed/eoapi-k8s/pull/149)

## [v0.4.15] - 2024-09-20

### Changed
- Postgrescluster chart upgrade [#148](https://github.com/developmentseed/eoapi-k8s/pull/148)

## [v0.4.14] - 2024-09-20

### Added
- Add NFS Option to PGBackRest [#147](https://github.com/developmentseed/eoapi-k8s/pull/147)

## [v0.4.13] - 2024-09-09

### Fixed
- Add back postgrescluster dependency to main eoapi chart [#145](https://github.com/developmentseed/eoapi-k8s/pull/145)

## [v0.4.10] - 2024-09-09

### Changed
- Move postgresql cluster file:// dependency to first-level chart dependency [#141](https://github.com/developmentseed/eoapi-k8s/pull/141)

## [v0.4.9] - 2024-09-04

### Fixed
- Fix horizontal pod autoscaling rules [#140](https://github.com/developmentseed/eoapi-k8s/pull/140)

### Changed
- Documentation updates [#139](https://github.com/developmentseed/eoapi-k8s/pull/139)

## [v0.4.8] - 2024-09-03

### Changed
- Default enable vector again [#138](https://github.com/developmentseed/eoapi-k8s/pull/138)

## [v0.4.7] - 2024-09-03

### Added
- Support and Autoscaling Additions [#135](https://github.com/developmentseed/eoapi-k8s/pull/135)

## [v0.4.6] - 2024-07-17

### Changed
- Bump chart patch versions [#131](https://github.com/developmentseed/eoapi-k8s/pull/131)

## [v0.4.2] - 2024-07-11

### Fixed
- Pin pypgstac versions [#126](https://github.com/developmentseed/eoapi-k8s/pull/126)

## [v0.4.1] - 2024-07-10

### Added
- Release Documentation and Cleanup [#117](https://github.com/developmentseed/eoapi-k8s/pull/117)

## [v0.4.0] - 2024-07-09

### Added
- Start EKS IAC with Docs Walkthrough from Notes [#12](https://github.com/developmentseed/eoapi-k8s/pull/12)
- Single Nginx Ingress and NLB with path rewrites [#11](https://github.com/developmentseed/eoapi-k8s/pull/11)
- Unit tests [#14](https://github.com/developmentseed/eoapi-k8s/pull/14)
- Document GKE k8s cluster setup [#27](https://github.com/developmentseed/eoapi-k8s/pull/27)
- Generalized commands and added livenessProbe [#35](https://github.com/developmentseed/eoapi-k8s/pull/35)
- HPA (CPU) draft before locust/artillery [#51](https://github.com/developmentseed/eoapi-k8s/pull/51)
- Autoscaling by request rate [#53](https://github.com/developmentseed/eoapi-k8s/pull/53)
- Support for specifying host and getting certs from cert manager [#60](https://github.com/developmentseed/eoapi-k8s/pull/60)
- Configuration for EKS autoscaler [#59](https://github.com/developmentseed/eoapi-k8s/pull/59)
- PGO by default [#84](https://github.com/developmentseed/eoapi-k8s/pull/84)
- Add fixtures [#9](https://github.com/developmentseed/eoapi-k8s/pull/9)
- Allow custom annotations [#66](https://github.com/developmentseed/eoapi-k8s/pull/66)
- Testing autoscaling in EKS [#55](https://github.com/developmentseed/eoapi-k8s/pull/55)

### Changed
- Default gitSha and insert main gitSha for distributed helm-chart [#21](https://github.com/developmentseed/eoapi-k8s/pull/21)
- Repository rename [#23](https://github.com/developmentseed/eoapi-k8s/pull/23)
- More explicit nginx documentation [#24](https://github.com/developmentseed/eoapi-k8s/pull/24)
- Root path HTML [#25](https://github.com/developmentseed/eoapi-k8s/pull/25)
- GKE related changes [#37](https://github.com/developmentseed/eoapi-k8s/pull/37)
- Release name for parallel CI tests [#43](https://github.com/developmentseed/eoapi-k8s/pull/43)
- API version update for release [#49](https://github.com/developmentseed/eoapi-k8s/pull/49)
- Upgraded pgstac, titiler-pgstac and tipg versions [#67](https://github.com/developmentseed/eoapi-k8s/pull/67)

### Fixed
- Database resources now can set limits and requests [#46](https://github.com/developmentseed/eoapi-k8s/pull/46)
- Integration tests with image upgrade [#68](https://github.com/developmentseed/eoapi-k8s/pull/68)
- Avoid immediate scaleup if autoscale is enabled [#52](https://github.com/developmentseed/eoapi-k8s/pull/52)
