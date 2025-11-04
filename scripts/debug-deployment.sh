#!/bin/bash

set -e

echo "=== Deployment Debug Information ==="

# Get release name from environment or detect it
RELEASE_NAME=${RELEASE_NAME:-$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=stac -o jsonpath='{.items[0].metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null || echo "eoapi")}
NAMESPACE=${NAMESPACE:-$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=stac -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "eoapi")}

echo "Using RELEASE_NAME: $RELEASE_NAME"
echo "Using NAMESPACE: $NAMESPACE"
echo ""

# eoAPI specific debugging
echo "--- eoAPI Namespace Status ---"
echo "Namespace info:"
kubectl get namespace "$NAMESPACE" -o wide 2>/dev/null || echo "Namespace $NAMESPACE not found"
echo ""
echo "All resources in eoAPI namespace:"
kubectl get all -n "$NAMESPACE" -o wide 2>/dev/null || echo "No resources found in namespace $NAMESPACE"
echo ""
echo "Jobs in eoAPI namespace:"
kubectl get jobs -n "$NAMESPACE" -o wide 2>/dev/null || echo "No jobs found in namespace $NAMESPACE"
echo ""
echo "ConfigMaps in eoAPI namespace:"
kubectl get configmaps -n "$NAMESPACE" 2>/dev/null || echo "No configmaps found in namespace $NAMESPACE"
echo ""
echo "Secrets in eoAPI namespace:"
kubectl get secrets -n "$NAMESPACE" 2>/dev/null || echo "No secrets found in namespace $NAMESPACE"
echo ""

# Helm status
echo "--- Helm Status ---"
echo "Helm releases in namespace $NAMESPACE:"
helm list -n "$NAMESPACE" -o table 2>/dev/null || echo "No helm releases found in namespace $NAMESPACE"
echo ""
echo "Helm release status:"
helm status "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Helm release $RELEASE_NAME not found in namespace $NAMESPACE"
echo ""

# Post-install hooks debugging
echo "--- Post-Install Hooks Status ---"
echo "pgstac-migrate job:"
kubectl get job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" -o wide 2>/dev/null || echo "pgstac-migrate job not found"
if kubectl get job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "pgstac-migrate job logs:"
  kubectl logs -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "No logs available for pgstac-migrate job"
  echo ""
  echo "pgstac-migrate job description:"
  kubectl describe job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" 2>/dev/null
fi
echo ""
echo "pgstac-load-samples job:"
kubectl get job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" -o wide 2>/dev/null || echo "pgstac-load-samples job not found"
if kubectl get job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "pgstac-load-samples job logs:"
  kubectl logs -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "No logs available for pgstac-load-samples job"
  echo ""
  echo "pgstac-load-samples job description:"
  kubectl describe job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" 2>/dev/null
fi
echo ""

# Basic cluster status
echo "--- Cluster Status ---"
kubectl get pods -o wide
kubectl get jobs -o wide
kubectl get services -o wide
kubectl get events --sort-by='.lastTimestamp' | tail -20 || true

# PostgreSQL status
echo "--- PostgreSQL Status ---"
echo "PostgreSQL clusters:"
kubectl get postgresclusters -n "$NAMESPACE" -o wide 2>/dev/null || echo "No PostgreSQL clusters found in namespace $NAMESPACE"
echo ""
echo "PostgreSQL pods:"
kubectl get pods -l postgres-operator.crunchydata.com/cluster -n "$NAMESPACE" -o wide 2>/dev/null || echo "No PostgreSQL pods found in namespace $NAMESPACE"
echo ""

# Traefik status
echo "--- Traefik Status ---"
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o wide || echo "No Traefik pods"
kubectl get crd | grep traefik || echo "No Traefik CRDs found"

# Ingress status
echo "--- Ingress Status ---"
kubectl get ingress -n "$NAMESPACE" -o wide 2>/dev/null || echo "No ingress resources in namespace $NAMESPACE"
kubectl get services -n "$NAMESPACE" -o wide 2>/dev/null || echo "No services in namespace $NAMESPACE"

# eoAPI notification system
echo "--- Notification System ---"
kubectl get deployments -l app.kubernetes.io/name=eoapi-notifier -n "$NAMESPACE" -o wide || echo "No eoapi-notifier deployment in namespace $NAMESPACE"

# Logs from key components
echo "--- Key Component Logs ---"
echo "STAC API logs:"
kubectl logs -l app.kubernetes.io/name=stac -n "$NAMESPACE" --tail=20 2>/dev/null || echo "No STAC API logs in namespace $NAMESPACE"
echo ""
echo "TiTiler logs:"
kubectl logs -l app.kubernetes.io/name=titiler -n "$NAMESPACE" --tail=20 2>/dev/null || echo "No TiTiler logs in namespace $NAMESPACE"
echo ""
echo "TiPG logs:"
kubectl logs -l app.kubernetes.io/name=tipg -n "$NAMESPACE" --tail=20 2>/dev/null || echo "No TiPG logs in namespace $NAMESPACE"
echo ""
echo "eoapi-notifier logs:"
kubectl logs -l app.kubernetes.io/name=eoapi-notifier -n "$NAMESPACE" --tail=20 2>/dev/null || echo "No eoapi-notifier logs in namespace $NAMESPACE"

# Recent events in eoAPI namespace
echo "--- Recent Events in eoAPI Namespace ---"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 2>/dev/null || echo "No events found in namespace $NAMESPACE"

# Resource usage
echo "--- Resource Usage ---"
echo "Node status:"
kubectl top nodes 2>/dev/null || echo "Metrics not available"
echo ""
echo "Pod resource usage in $NAMESPACE:"
kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Pod metrics not available"
