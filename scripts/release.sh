#!/bin/sh

export RELEASE_NAME=eoapi
export RELEASE_NS=eoapi
export SUPPORT_RELEASE_NAME=eoapi-support
export SUPPORT_RELEASE_NS=eoapi

helm upgrade --install \
  -n $SUPPORT_RELEASE_NS --create-namespace $SUPPORT_RELEASE_NAME \
  eoapi/eoapi-support --version 0.1.5 \
  --set prometheus-adapter.prometheus.url='http://${SUPPORT_RELEASE_NAME}-prometheus-server.${SUPPORT_RELEASE_NS}.svc.cluster.local' \
  --set grafana.datasources.datasources\\.yaml.datasources[0].url='http://${SUPPORT_RELEASE_NAME}-prometheus-server.${SUPPORT_RELEASE_NS}.svc.cluster.local' \
  -f /Users/ranchodeluxe/apps/eoapi-k8s/helm-chart/eoapi-support/values.yaml

helm upgrade --install \
  -n $RELEASE_NS --create-namespace $RELEASE_NAME \
  eoapi/eoapi --version 0.4.8 \
  -f /Users/ranchodeluxe/apps/eoapi-k8s/helm-chart/eoapi/values.yaml


