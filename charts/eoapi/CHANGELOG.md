# Changelog

## [0.9.0](https://github.com/developmentseed/eoapi-k8s/compare/v0.8.1...v0.9.0) (2026-01-14)


### Added

* Add auth for stac browser. ([#376](https://github.com/developmentseed/eoapi-k8s/issues/376)) ([83db491](https://github.com/developmentseed/eoapi-k8s/commit/83db4915e45d3bc7f052c73158000c18ceb14c27))
* Add support for job annotations in pgstac bootstrap configuration ([#381](https://github.com/developmentseed/eoapi-k8s/issues/381)) ([761bb49](https://github.com/developmentseed/eoapi-k8s/commit/761bb495f474dc8338a0f2bf71362c8913b3f4c2))


### Fixed

* Add queryables file name check ([#380](https://github.com/developmentseed/eoapi-k8s/issues/380)) ([fba8c9f](https://github.com/developmentseed/eoapi-k8s/commit/fba8c9f4d902c632496e14c58d48dbabd2fd404e))


### Changed

* Consolidate data directory ([#387](https://github.com/developmentseed/eoapi-k8s/issues/387)) ([333aa4d](https://github.com/developmentseed/eoapi-k8s/commit/333aa4d1ee0240124b83749042688472d9a7e256))
* Some more CI consistency. ([#406](https://github.com/developmentseed/eoapi-k8s/issues/406)) ([adc29cf](https://github.com/developmentseed/eoapi-k8s/commit/adc29cfe331de1141ec4c1502d3fb0981732a3d2))


### Maintenance

* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.4 ([#378](https://github.com/developmentseed/eoapi-k8s/issues/378)) ([591c129](https://github.com/developmentseed/eoapi-k8s/commit/591c12914c4768b253411d85de2a79c6cd8ebaf7))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.5 ([#385](https://github.com/developmentseed/eoapi-k8s/issues/385)) ([f658b16](https://github.com/developmentseed/eoapi-k8s/commit/f658b168d8d746656a420e06ce520f9d85194c0a))
* **deps:** updated helm release grafana to 10.3.1. ([#383](https://github.com/developmentseed/eoapi-k8s/issues/383)) ([d0bbe96](https://github.com/developmentseed/eoapi-k8s/commit/d0bbe962afae7eabb8ba6cf420b4b8656a9f34e5))
* **deps:** updated helm release grafana to 10.3.2. ([#390](https://github.com/developmentseed/eoapi-k8s/issues/390)) ([1bd0be4](https://github.com/developmentseed/eoapi-k8s/commit/1bd0be456e4a7daec71a85385903e4015cf38adb))
* **deps:** updated helm release grafana to 10.4.0. ([#391](https://github.com/developmentseed/eoapi-k8s/issues/391)) ([5bfb3bb](https://github.com/developmentseed/eoapi-k8s/commit/5bfb3bb2b1fa91df09829217833d2205ba925983))
* **deps:** updated helm release grafana to 10.4.3. ([#393](https://github.com/developmentseed/eoapi-k8s/issues/393)) ([d7a4741](https://github.com/developmentseed/eoapi-k8s/commit/d7a4741fab9b21dfb8bfcd83f85d01a9e9497047))
* **deps:** updated helm release grafana to 10.5.2. ([#395](https://github.com/developmentseed/eoapi-k8s/issues/395)) ([d7fd994](https://github.com/developmentseed/eoapi-k8s/commit/d7fd994cb5739cd2a1748565acc5e5ad734b4b6f))
* **deps:** updated helm release grafana to 10.5.4. ([#396](https://github.com/developmentseed/eoapi-k8s/issues/396)) ([c5acdaf](https://github.com/developmentseed/eoapi-k8s/commit/c5acdaf25906a18225f1214cd1e6db21a49bedab))
* **deps:** updated helm release grafana to 10.5.5. ([#399](https://github.com/developmentseed/eoapi-k8s/issues/399)) ([c01bb47](https://github.com/developmentseed/eoapi-k8s/commit/c01bb471ab9d97840d55da269529dba59b9cd70e))
* **deps:** updated helm release grafana to 10.5.6. ([#402](https://github.com/developmentseed/eoapi-k8s/issues/402)) ([0cf94ad](https://github.com/developmentseed/eoapi-k8s/commit/0cf94ad00c6008c228a264289764257e452bfe07))
* **deps:** updated helm release prometheus to 27.50.1. ([#379](https://github.com/developmentseed/eoapi-k8s/issues/379)) ([d3fc17e](https://github.com/developmentseed/eoapi-k8s/commit/d3fc17eeb5246e81221edd3887fafc84bcb84289))
* **deps:** updated helm release prometheus to 27.52.0. ([#389](https://github.com/developmentseed/eoapi-k8s/issues/389)) ([a7196f1](https://github.com/developmentseed/eoapi-k8s/commit/a7196f1d25e5fbec8046e8b8e6565f4f327db692))
* **deps:** updated helm release prometheus to 28.0.0. ([#394](https://github.com/developmentseed/eoapi-k8s/issues/394)) ([e2ac055](https://github.com/developmentseed/eoapi-k8s/commit/e2ac055e1a691992d097dcfe3a42a53fbc485077))
* **deps:** updated helm release prometheus to 28.2.1. ([#397](https://github.com/developmentseed/eoapi-k8s/issues/397)) ([f2111d1](https://github.com/developmentseed/eoapi-k8s/commit/f2111d116c2a9937580d46d33c20e2722c3ab911))
* **deps:** updated helm release prometheus to 28.3.0. ([#400](https://github.com/developmentseed/eoapi-k8s/issues/400)) ([641231c](https://github.com/developmentseed/eoapi-k8s/commit/641231c903ac06f1842bdf33e93db3d62353cbe2))
* **deps:** updated stac-auth-proxy docker tag to v0.1.2 ([#392](https://github.com/developmentseed/eoapi-k8s/issues/392)) ([f78357c](https://github.com/developmentseed/eoapi-k8s/commit/f78357cd22b5a51fe5d5119633a9c781972e0eb6))
* **deps:** updated stac-auth-proxy to 0.11.1. ([#404](https://github.com/developmentseed/eoapi-k8s/issues/404)) ([ba35dd9](https://github.com/developmentseed/eoapi-k8s/commit/ba35dd938297c882a6a848f62c68f54892905bd4))
* Upgraded titiler-pgstac to 2.0.0. ([#401](https://github.com/developmentseed/eoapi-k8s/issues/401)) ([9326579](https://github.com/developmentseed/eoapi-k8s/commit/932657978499c072d7890d34790a00ec88d5181b))
