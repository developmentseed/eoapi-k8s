# Changelog

## 1.0.0 (2026-01-14)


### Added

* Add auth for stac browser. ([#376](https://github.com/developmentseed/eoapi-k8s/issues/376)) ([83db491](https://github.com/developmentseed/eoapi-k8s/commit/83db4915e45d3bc7f052c73158000c18ceb14c27))
* Add autoscaling tests ([#343](https://github.com/developmentseed/eoapi-k8s/issues/343)) ([1253640](https://github.com/developmentseed/eoapi-k8s/commit/125364021882372abc14e480433ccfd2a4d1dc83))
* Add checksums to configmaps ([#344](https://github.com/developmentseed/eoapi-k8s/issues/344)) ([e5d82da](https://github.com/developmentseed/eoapi-k8s/commit/e5d82da3fb29345aeb1fafa2eac1dbcc753328b4))
* Add clarification about concurrency and db connection configuration. ([#356](https://github.com/developmentseed/eoapi-k8s/issues/356)) ([1943630](https://github.com/developmentseed/eoapi-k8s/commit/1943630cef4c965e5e0f11d568d9aa3e472a3fb5))
* Add Knative integration for notifications ([#316](https://github.com/developmentseed/eoapi-k8s/issues/316)) ([3e01468](https://github.com/developmentseed/eoapi-k8s/commit/3e01468981c2c85db09e4802df4f7db158e24b78))
* Add more pgstac config options. ([#340](https://github.com/developmentseed/eoapi-k8s/issues/340)) ([6622cdb](https://github.com/developmentseed/eoapi-k8s/commit/6622cdb722e04c72e7165eb7b5dea4b1001f3ea9))
* Add observability tests ([#342](https://github.com/developmentseed/eoapi-k8s/issues/342)) ([0158411](https://github.com/developmentseed/eoapi-k8s/commit/0158411529c492528c4e281fd4b6e59ee21040fa))
* Add profile for production. ([#354](https://github.com/developmentseed/eoapi-k8s/issues/354)) ([7703aa9](https://github.com/developmentseed/eoapi-k8s/commit/7703aa97788b172494d62e40824476e01aef748a))
* Add pubsub notifications ([#289](https://github.com/developmentseed/eoapi-k8s/issues/289)) ([e9fbd0a](https://github.com/developmentseed/eoapi-k8s/commit/e9fbd0acb56b37b14ab889176f2a447094c9d738))
* Add queryables configuration support in pgstac bootstrap ([#323](https://github.com/developmentseed/eoapi-k8s/issues/323)) ([212f0c9](https://github.com/developmentseed/eoapi-k8s/commit/212f0c96b369f158ce1fd717aea5b6636b22c696))
* add some missing metadata and enable annotations on browser service ([#255](https://github.com/developmentseed/eoapi-k8s/issues/255)) ([15071a7](https://github.com/developmentseed/eoapi-k8s/commit/15071a7f9d703972cbdf00b2c78a5da171c077b3))
* Add stac-auth-proxy. ([#358](https://github.com/developmentseed/eoapi-k8s/issues/358)) ([23f6fb9](https://github.com/developmentseed/eoapi-k8s/commit/23f6fb9e926970983c08530c557d04539e6e12a7))
* Add support for job annotations in pgstac bootstrap configuration ([#381](https://github.com/developmentseed/eoapi-k8s/issues/381)) ([761bb49](https://github.com/developmentseed/eoapi-k8s/commit/761bb495f474dc8338a0f2bf71362c8913b3f4c2))
* Added support for ConfigMap reference-based queryables configuration ([#360](https://github.com/developmentseed/eoapi-k8s/issues/360)) ([0b12f37](https://github.com/developmentseed/eoapi-k8s/commit/0b12f37027a110eda73dc491804a7314ebed56a6))
* prep 0.7.7 release ([#258](https://github.com/developmentseed/eoapi-k8s/issues/258)) ([c59b991](https://github.com/developmentseed/eoapi-k8s/commit/c59b9919ce0999bdc353e82f348683a4dc97839d))
* prep 0.7.8 release ([#287](https://github.com/developmentseed/eoapi-k8s/issues/287)) ([15febec](https://github.com/developmentseed/eoapi-k8s/commit/15febecdfda976914c4c7b401a2ebf402565941e))
* prep for release of 0.7.6 ([#256](https://github.com/developmentseed/eoapi-k8s/issues/256)) ([a282047](https://github.com/developmentseed/eoapi-k8s/commit/a2820471f312f487d4c84a914b1e905557b8dd06))


### Fixed

* Add queryables file name check ([#380](https://github.com/developmentseed/eoapi-k8s/issues/380)) ([fba8c9f](https://github.com/developmentseed/eoapi-k8s/commit/fba8c9f4d902c632496e14c58d48dbabd2fd404e))
* Allow setting stac.overrideRootPath to empty string for stac-auth-proxy integration ([#307](https://github.com/developmentseed/eoapi-k8s/issues/307)) ([f1035bd](https://github.com/developmentseed/eoapi-k8s/commit/f1035bdc518d7afb815360b61828d7a8fc48a396))
* Call run_queued_queries procedure. ([#377](https://github.com/developmentseed/eoapi-k8s/issues/377)) ([6f889ba](https://github.com/developmentseed/eoapi-k8s/commit/6f889baf5107c3709385dda177fe31964fef354b))
* Disable VRT support in TiTiler by default ([#243](https://github.com/developmentseed/eoapi-k8s/issues/243)) ([bf14a5f](https://github.com/developmentseed/eoapi-k8s/commit/bf14a5f395e700bcc2791f95ab36249081ee5eda))
* enable annotations on multidim,raster,stac,vector ([#286](https://github.com/developmentseed/eoapi-k8s/issues/286)) ([a3644ce](https://github.com/developmentseed/eoapi-k8s/commit/a3644ce0f3528124ee3281a7239d9ebdae777d0c))
* Helper for postgrescluster.enabled false when using external db ([#346](https://github.com/developmentseed/eoapi-k8s/issues/346)) ([d853034](https://github.com/developmentseed/eoapi-k8s/commit/d85303448d2c5612be43a3864a97fcd42a6cb462))
* Name behavior field consistently. ([#345](https://github.com/developmentseed/eoapi-k8s/issues/345)) ([59e0c78](https://github.com/developmentseed/eoapi-k8s/commit/59e0c781074d4eba18c7903505ec83b62a29e7d2))


### Changed

* auto-scaling and observability components ([#262](https://github.com/developmentseed/eoapi-k8s/issues/262)) ([12f7097](https://github.com/developmentseed/eoapi-k8s/commit/12f709745e4ca6dc5c22a75af78b15382d998840))
* Consolidate data directory ([#387](https://github.com/developmentseed/eoapi-k8s/issues/387)) ([333aa4d](https://github.com/developmentseed/eoapi-k8s/commit/333aa4d1ee0240124b83749042688472d9a7e256))
* documentation structure. ([#318](https://github.com/developmentseed/eoapi-k8s/issues/318)) ([8b575b7](https://github.com/developmentseed/eoapi-k8s/commit/8b575b7e1a241d20bbb957631897c96f4586c9f6))
* Improve code formatting ([#283](https://github.com/developmentseed/eoapi-k8s/issues/283)) ([fe422c4](https://github.com/developmentseed/eoapi-k8s/commit/fe422c4dbb1d6214a064d90f9ab3e9482ca0f5ce))
* Improved CI and local debugging. ([#326](https://github.com/developmentseed/eoapi-k8s/issues/326)) ([38a67c3](https://github.com/developmentseed/eoapi-k8s/commit/38a67c38ac2ca9f2abfd8aeda5e3f251d2f31ede))
* Remove unused testing variable. ([#369](https://github.com/developmentseed/eoapi-k8s/issues/369)) ([25d8f14](https://github.com/developmentseed/eoapi-k8s/commit/25d8f145f308ba43a4884547f8c5c2eb57090df0))
* Reorganize template files. ([#352](https://github.com/developmentseed/eoapi-k8s/issues/352)) ([8f2e780](https://github.com/developmentseed/eoapi-k8s/commit/8f2e7806f2c09ef37ec07f95c2b33821809afbce))
* Restructured values in service profiles. ([#351](https://github.com/developmentseed/eoapi-k8s/issues/351)) ([ef171ab](https://github.com/developmentseed/eoapi-k8s/commit/ef171ab44ae13c88255dc7758a2f5bfb34a8bdec))
* Simplify resource definitions. ([#357](https://github.com/developmentseed/eoapi-k8s/issues/357)) ([c67dfa1](https://github.com/developmentseed/eoapi-k8s/commit/c67dfa19d86ec9752f90da1d64a779d536efb592))
* Some more CI consistency. ([#406](https://github.com/developmentseed/eoapi-k8s/issues/406)) ([409dc4a](https://github.com/developmentseed/eoapi-k8s/commit/409dc4abe5f597e7a6d18474157752ef7ceb8e3d))
* Streamline scripts into unified eoapi-cli command ([#359](https://github.com/developmentseed/eoapi-k8s/issues/359)) ([02ed183](https://github.com/developmentseed/eoapi-k8s/commit/02ed18367cea58578cf260b270aef4e5395e3f1b))


### Maintenance

* **deps:** updated eoapi-notifier docker tag to v0.0.8 ([#321](https://github.com/developmentseed/eoapi-k8s/issues/321)) ([6e471e4](https://github.com/developmentseed/eoapi-k8s/commit/6e471e4ea1682abbc8e319d8a6a10c8fd16a7f18))
* **deps:** updated ghcr.io/developmentseed/tipg docker tag to v1.3.0 ([#355](https://github.com/developmentseed/eoapi-k8s/issues/355)) ([ec37b0c](https://github.com/developmentseed/eoapi-k8s/commit/ec37b0c694763125123df580db8e42bbefe797bf))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.0.2 ([#308](https://github.com/developmentseed/eoapi-k8s/issues/308)) ([674c54a](https://github.com/developmentseed/eoapi-k8s/commit/674c54acd72f23f0cf3e9be885f9cdb7073d3c0b))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.0 ([#329](https://github.com/developmentseed/eoapi-k8s/issues/329)) ([64c5d8b](https://github.com/developmentseed/eoapi-k8s/commit/64c5d8b8d7b943006cc160a4a7ddf7132a58f8b4))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.1 ([#362](https://github.com/developmentseed/eoapi-k8s/issues/362)) ([fbdf776](https://github.com/developmentseed/eoapi-k8s/commit/fbdf77676b8f15609c8ac55e7d78637d772ba1ae))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.2 ([#368](https://github.com/developmentseed/eoapi-k8s/issues/368)) ([ec6d93f](https://github.com/developmentseed/eoapi-k8s/commit/ec6d93f7d0aa347325f8f1ce2748704c4c2051b5))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.4 ([#378](https://github.com/developmentseed/eoapi-k8s/issues/378)) ([591c129](https://github.com/developmentseed/eoapi-k8s/commit/591c12914c4768b253411d85de2a79c6cd8ebaf7))
* **deps:** updated ghcr.io/stac-utils/stac-fastapi-pgstac docker tag to v6.1.5 ([#385](https://github.com/developmentseed/eoapi-k8s/issues/385)) ([f658b16](https://github.com/developmentseed/eoapi-k8s/commit/f658b168d8d746656a420e06ce520f9d85194c0a))
* **deps:** updated ghcr.io/stac-utils/titiler-pgstac docker tag to v1.9.0 ([#305](https://github.com/developmentseed/eoapi-k8s/issues/305)) ([8602053](https://github.com/developmentseed/eoapi-k8s/commit/8602053a4eb6bf9417ce266e94a7ba448dcc25cc))
* **deps:** updated helm release grafana to 10.1.5. ([#361](https://github.com/developmentseed/eoapi-k8s/issues/361)) ([4a7185f](https://github.com/developmentseed/eoapi-k8s/commit/4a7185f1edec8cdaa28c0ca1554ce1f57c044ea2))
* **deps:** updated helm release grafana to 10.2.0. ([#365](https://github.com/developmentseed/eoapi-k8s/issues/365)) ([a718c18](https://github.com/developmentseed/eoapi-k8s/commit/a718c189122e018e02212b86225a8dc86732fd2c))
* **deps:** updated helm release grafana to 10.3.0. ([#375](https://github.com/developmentseed/eoapi-k8s/issues/375)) ([de8657f](https://github.com/developmentseed/eoapi-k8s/commit/de8657fa3c8d6a1e0d64369cf26a1ba91d3c5f84))
* **deps:** updated helm release grafana to 10.3.1. ([#383](https://github.com/developmentseed/eoapi-k8s/issues/383)) ([d0bbe96](https://github.com/developmentseed/eoapi-k8s/commit/d0bbe962afae7eabb8ba6cf420b4b8656a9f34e5))
* **deps:** updated helm release grafana to 10.3.2. ([#390](https://github.com/developmentseed/eoapi-k8s/issues/390)) ([1bd0be4](https://github.com/developmentseed/eoapi-k8s/commit/1bd0be456e4a7daec71a85385903e4015cf38adb))
* **deps:** updated helm release grafana to 10.4.0. ([#391](https://github.com/developmentseed/eoapi-k8s/issues/391)) ([5bfb3bb](https://github.com/developmentseed/eoapi-k8s/commit/5bfb3bb2b1fa91df09829217833d2205ba925983))
* **deps:** updated helm release grafana to 10.4.3. ([#393](https://github.com/developmentseed/eoapi-k8s/issues/393)) ([d7a4741](https://github.com/developmentseed/eoapi-k8s/commit/d7a4741fab9b21dfb8bfcd83f85d01a9e9497047))
* **deps:** updated helm release grafana to 10.5.2. ([#395](https://github.com/developmentseed/eoapi-k8s/issues/395)) ([d7fd994](https://github.com/developmentseed/eoapi-k8s/commit/d7fd994cb5739cd2a1748565acc5e5ad734b4b6f))
* **deps:** updated helm release grafana to 10.5.4. ([#396](https://github.com/developmentseed/eoapi-k8s/issues/396)) ([c5acdaf](https://github.com/developmentseed/eoapi-k8s/commit/c5acdaf25906a18225f1214cd1e6db21a49bedab))
* **deps:** updated helm release grafana to 10.5.5. ([#399](https://github.com/developmentseed/eoapi-k8s/issues/399)) ([c01bb47](https://github.com/developmentseed/eoapi-k8s/commit/c01bb471ab9d97840d55da269529dba59b9cd70e))
* **deps:** updated helm release grafana to 10.5.6. ([#402](https://github.com/developmentseed/eoapi-k8s/issues/402)) ([0cf94ad](https://github.com/developmentseed/eoapi-k8s/commit/0cf94ad00c6008c228a264289764257e452bfe07))
* **deps:** updated helm release knative-operator to v1.19.5. ([#330](https://github.com/developmentseed/eoapi-k8s/issues/330)) ([40b74ab](https://github.com/developmentseed/eoapi-k8s/commit/40b74ab97eab19a6093e2ed47624ac7d6b060ca3))
* **deps:** updated helm release knative-operator to v1.20.0. ([#337](https://github.com/developmentseed/eoapi-k8s/issues/337)) ([16631e1](https://github.com/developmentseed/eoapi-k8s/commit/16631e1a24ca2157eb0f477b4d7854fd19942a5f))
* **deps:** updated helm release prometheus to 27.46.0. ([#366](https://github.com/developmentseed/eoapi-k8s/issues/366)) ([0efe090](https://github.com/developmentseed/eoapi-k8s/commit/0efe09096758e754ea8be5c7cfd004d66521d82f))
* **deps:** updated helm release prometheus to 27.49.0. ([#374](https://github.com/developmentseed/eoapi-k8s/issues/374)) ([23982e6](https://github.com/developmentseed/eoapi-k8s/commit/23982e6521c285bdc1ce6b41dd3410e2543549cc))
* **deps:** updated helm release prometheus to 27.50.1. ([#379](https://github.com/developmentseed/eoapi-k8s/issues/379)) ([d3fc17e](https://github.com/developmentseed/eoapi-k8s/commit/d3fc17eeb5246e81221edd3887fafc84bcb84289))
* **deps:** updated helm release prometheus to 27.52.0. ([#389](https://github.com/developmentseed/eoapi-k8s/issues/389)) ([a7196f1](https://github.com/developmentseed/eoapi-k8s/commit/a7196f1d25e5fbec8046e8b8e6565f4f327db692))
* **deps:** updated helm release prometheus to 28.0.0. ([#394](https://github.com/developmentseed/eoapi-k8s/issues/394)) ([e2ac055](https://github.com/developmentseed/eoapi-k8s/commit/e2ac055e1a691992d097dcfe3a42a53fbc485077))
* **deps:** updated helm release prometheus to 28.2.1. ([#397](https://github.com/developmentseed/eoapi-k8s/issues/397)) ([f2111d1](https://github.com/developmentseed/eoapi-k8s/commit/f2111d116c2a9937580d46d33c20e2722c3ab911))
* **deps:** updated helm release prometheus to 28.3.0. ([#400](https://github.com/developmentseed/eoapi-k8s/issues/400)) ([641231c](https://github.com/developmentseed/eoapi-k8s/commit/641231c903ac06f1842bdf33e93db3d62353cbe2))
* **deps:** updated registry.k8s.io/ingress-nginx/kube-webhook-certgen docker tag to v1.6.4 ([#332](https://github.com/developmentseed/eoapi-k8s/issues/332)) ([2716ca3](https://github.com/developmentseed/eoapi-k8s/commit/2716ca3796e05ce0e2fce59c12065ed00608be72))
* **deps:** updated registry.k8s.io/ingress-nginx/kube-webhook-certgen docker tag to v1.6.5 ([#372](https://github.com/developmentseed/eoapi-k8s/issues/372)) ([bd095a0](https://github.com/developmentseed/eoapi-k8s/commit/bd095a083b72d55ad95cfd8f73383a53b7b96c4d))
* **deps:** updated stac-auth-proxy docker tag to v0.1.2 ([#392](https://github.com/developmentseed/eoapi-k8s/issues/392)) ([f78357c](https://github.com/developmentseed/eoapi-k8s/commit/f78357cd22b5a51fe5d5119633a9c781972e0eb6))
* **deps:** updated stac-auth-proxy to 0.11.1. ([#404](https://github.com/developmentseed/eoapi-k8s/issues/404)) ([ba35dd9](https://github.com/developmentseed/eoapi-k8s/commit/ba35dd938297c882a6a848f62c68f54892905bd4))
* prep release for 0.7.10 ([#310](https://github.com/developmentseed/eoapi-k8s/issues/310)) ([6b29122](https://github.com/developmentseed/eoapi-k8s/commit/6b29122a0ad452e4b7dfbea945a7f9b79a5b5fba))
* Release/0.8.0 ([#353](https://github.com/developmentseed/eoapi-k8s/issues/353)) ([922925c](https://github.com/developmentseed/eoapi-k8s/commit/922925c95d4752d11e975b80f9dc7ff9ee75c218))
* Upgraded titiler-pgstac to 2.0.0. ([#401](https://github.com/developmentseed/eoapi-k8s/issues/401)) ([9326579](https://github.com/developmentseed/eoapi-k8s/commit/932657978499c072d7890d34790a00ec88d5181b))
