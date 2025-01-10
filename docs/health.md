# Health checks and liveness probes

All services in eoAPI have endpoints for basic health checks. 
The deployment template includes instructions for these checks to get pinged on a regular basis - look for `livenessProbe` 
in https://github.com/developmentseed/eoapi-k8s/blob/main/helm-chart/eoapi/templates/services/deployment.yaml
