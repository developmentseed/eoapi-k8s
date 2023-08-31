version numbers below correspond to helm chart `appVersion`: see ./helm-chart/eoapi/Chart.yaml
---
# 0.1.2 (2023-08-31)

* move `command` blocks out to `values.yml` for [generalizing ticket](https://github.com/developmentseed/eoapi-k8s/issues/31)

# 0.1.1 (2023-07-21)

* For the shared-nginx ingress option [add root path with docs](https://github.com/developmentseed/eoapi-k8s/issues/18) pointing to path rewrites

# 0.1.0 (2023-07-01)

* Adds basic AWS EKS services with ALB and NLB options
