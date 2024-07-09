version numbers below correspond to helm chart `appVersion`: see `./helm-chart/eoapi/Chart.yaml`
---
### 0.3.5 (2024-07-09)

* tweaks for getting NFS working with a static NFS EFS mount

### 0.3.4 (2024-07-05)

* add back in a hidden non-pgo option for EOEPCA+ 

### 0.3.3 (2024-06-26)

* add k3 integration tests
* break out GCP integreation tests and force them to use TLS
* clean it up

### 0.3.2 (2024-06-16)

* backward breaking change: remove in-memory postgres database and secret management for crunchydata postgresql cluster

### 0.3.1 (2024-01-19)

* removed support for having anything but `ingresss.className=='nginx'`

### 0.2.11 (2024-01-18)

* added `ingress.annotations` key to pass through to the nginx ingress -- thanks @ghelobytes
* upgraded titiler/pgstac/tipg images and integration tests  -- thanks @vincentsarago
* added autoscaling permissions and docs to the AWS walkthrough -- thanks @Rub21

### 0.2.10 (2023-11-22)

* give `ingress.className == "nginx"` the ability pass hosts and tls information
* more tests to give user feedback about the above functionality if the wrong `ingress.className` was given

### 0.2.9 (2023-10-25)

* removed `providerContext` and any support for minikube from the templates so this is a breaking change
* added autoscaling rules and docs based on request rate using prometheus + ingress nginx controller + prometheus-adapter

### 0.1.8 (2023-10-02)

* adjust cpu limits so if autoscaling is enabled it doesn't immediately scaleup

### 0.1.7 (2023-10-02)

* adds `autoscaling` options to each service for HPA

### 0.1.6 (2023-09-27)

* adds `docServer.enable` flag to the `values.yaml` and service templates

### 0.1.5 (2023-09-16)

* adds a cpu and memory limits/requests to the `db` config block

### 0.1.4 (2023-09-09)

* adds a `testing: false` value to `values.yaml`
* plumb through `{{ $.Release.Name }}` into all the right templates so our CI can `helm install` into a single namespace and run tests in parallel

### 0.1.3 (2023-09-05)

* test on GKE and add documentation where needed for [GKE template changes](https://github.com/developmentseed/eoapi-k8s/issues/29)
* CI/CD should run on GKE so we debug less test failures on minikube for [move CI/CD away from minikube](https://github.com/developmentseed/eoapi-k8s/issues/36)
* documentation about default configuration and additional options for [documentation](https://github.com/developmentseed/eoapi-k8s/issues/19)

### 0.1.2 (2023-08-31)

* move `command` blocks out to `values.yml` for [generalizing ticket](https://github.com/developmentseed/eoapi-k8s/issues/31)
* add `livenessProbe` for all deployments for [livenessProbe bug](https://github.com/developmentseed/eoapi-k8s/issues/26)

### 0.1.1 (2023-07-21)

* For the shared-nginx ingress option [add root path with docs](https://github.com/developmentseed/eoapi-k8s/issues/18) pointing to path rewrites

### 0.1.0 (2023-07-01)

* Adds basic AWS EKS services with ALB and NLB options
