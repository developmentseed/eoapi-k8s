# Makefile for eoapi-k8s

# Variables
HELM_REPO_URL=https://devseed.com/eoapi-k8s/
HELM_CHART_NAME=eoapi/eoapi
PGO_CHART_VERSION=5.7.0

.PHONY: all deploy minikube ingest help

# Default target
all: deploy

deploy:
	@echo "Installing dependencies."
	@command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed"; exit 1; }
	helm install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo --version $(PGO_CHART_VERSION)
	@echo "Adding eoAPI helm repository."
	@helm repo add eoapi $(HELM_REPO_URL)
	@echo "Installing eoAPI helm chart."
	@cd ./helm-chart && \
	helm dependency build ./eoapi && \
	helm install --namespace eoapi --create-namespace --set gitSha=$$(git rev-parse HEAD | cut -c1-10) eoapi ./eoapi

minikube:
	@echo "Starting minikube."
	@command -v minikube >/dev/null 2>&1 || { echo "minikube is required but not installed"; exit 1; }
	minikube start
	# Deploy eoAPI via the regular helm install routine
	@make deploy
	minikube addons enable ingress
	@echo "eoAPI is now available at:"
	@minikube service ingress-nginx-controller -n ingress-nginx --url | head -n 1

ingest:
	@echo "Ingesting STAC collections and items into the database."
	@command -v bash >/dev/null 2>&1 || { echo "bash is required but not installed"; exit 1; }
	@./ingest.sh || { echo "Ingestion failed."; exit 1; }

help:
	@echo "Makefile commands:"
	@echo "  make deploy         -  Install eoAPI on a cluster kubectl is connected to."
	@echo "  make minikube       -  Install eoAPI on minikube."
	@echo "  make ingest         -  Ingest STAC collections and items into the database."
	@echo "  make help           -  Show this help message."
