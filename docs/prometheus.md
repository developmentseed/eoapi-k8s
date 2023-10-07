## Installing Prometheus and Grafana in the Cluster

### Prometheus:

Prometheus is a monitoring tool that helps you keep track of various metrics and statistics for your computer systems, applications, and services. It collects data over time(stores 15days), allowing you to analyze performance, troubleshoot issues.

### Exporters: https://prometheus.io/docs/instrumenting/exporters/

Exporters are programs that collect metrics from a specified source and transform them into a format that can be consumed by Prometheus.

- [Node_exporter](https://github.com/prometheus/node_exporter)

The `node_exporter` is designed to collect metrics from the host system, for Unix-like systems.
By default, the installation of Prometheus includes node_exporter. This exporter gathers system information such as CPU usage, memory, disk usage, and more, and presents it in a format that Prometheus can collect.


- [cAdvisor](https://github.com/google/cadvisor)

`cAdvisor` (Container Advisor) is an open-source monitoring tool for containers. it provides detailed information about resource usage and performance characteristics of running containers.

## Installing  Prometheus, Grafana and exporters


```sh
# Create prometheus namespace
kubectl create namespace prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Installing prometheus & Grafana & node-exporter
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
--namespace prometheus \
--set grafana.enabled=true \
--set-string grafana.adminPassword=1234 

# Installing cAdvisor
helm repo add ckotzbauer https://ckotzbauer.github.io/helm-charts/
helm repo update
helm search repo cadvisor
helm upgrade --install cadvisor ckotzbauer/cadvisor --namespace prometheus

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    jobLabel: cadvisor
    release: prometheus
  name: cadvisor
  namespace: prometheus
spec:
  attachMetadata:
    node: false
  endpoints:
  - port: http
    scheme: http
  jobLabel: jobLabel
  selector:
    matchLabels:
      release: prometheus
EOF
```
## Remove Prometheus, Grafana and exporters

```sh
helm delete prometheus --namespace prometheus
helm delete cadvisor --namespace prometheus
```

## Enable UI dashboards

### Prometheus dashboard

```sh
kubectl port-forward svc/prometheus-operated 9090 --namespace prometheus
```


http://localhost:9090/targets?search=


### Grafana dashboard

```sh
kubectl port-forward deployment/prometheus-grafana 3000 --namespace prometheus
```
http://localhost:3000


The dashboards can be customized for each specific use case. There are still more metrics to explore that could be useful or necessary for the EOAPI scenario.


