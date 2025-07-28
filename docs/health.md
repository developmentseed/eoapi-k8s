# Health checks and liveness probes

All services in eoAPI have endpoints for basic health checks.
The deployment template includes instructions for these checks to get pinged on a regular basis - look for `livenessProbe`
in https://github.com/developmentseed/eoapi-k8s/blob/main/charts/eoapi/templates/services/deployment.yaml

If you are using the default ingress setup, the health endpoints are:

* Raster API: `/raster/healthz`, success: returns status code 200, no auth
* Vector API: `/vector/healthz`, success: returns status code 200, no auth
* STAC API: `/stac/_mgmt/ping`, sucess: returns status code 200, no auth
