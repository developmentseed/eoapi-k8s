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

## Installing  Prometheus, Grafana and exporters: 

Clone the repo: https://github.com/Rub21/k8s-monitoring

To access the Grafana dashboard, you'll need to set up an environment variable. For example, use the command `export GRAFANA_ADMIN_PASSWORD=abcd`. By default, the password is set to 1234.


```sh

./deploy.sh create
# tab1
kubectl port-forward svc/prometheus-operated 9090 --namespace prometheus
# tab2
kubectl port-forward deployment/prometheus-grafana 3000 --namespace prometheus
```


Once the UI dashboards are exported, you can open them.


### Prometheus dashboard

http://localhost:9090/targets?search=

<img width="1323" alt="image" src="https://github.com/developmentseed/eoapi-k8s/assets/1152236/b3134e1a-8253-4221-8646-63e989fe9b3e">

### Grafana dashboard

-  Node exporter
http://localhost:3000/d/rYdddlPWk/node-exporter-full?orgId=1
<img width="1232" alt="image" src="https://github.com/developmentseed/eoapi-k8s/assets/1152236/bc7557bd-8d19-4492-acac-4415d69bb188">

- cAdvisor
<img width="1322" alt="image" src="https://github.com/developmentseed/eoapi-k8s/assets/1152236/593bfe59-3e7e-40df-8ba4-13a31c391581">



The dashboards can be customized for each specific use case. There are still more metrics to explore that could be useful or necessary for the EOAPI scenario.


