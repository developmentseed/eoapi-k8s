# Makefile for eoapi-k8s

# Variables
HELM_REPO_URL=https://devseed.com/eoapi-k8s/
HELM_CHART_NAME=eoapi/eoapi
PGO_CHART_VERSION=5.7.4

.PHONY: all deploy minikube ingest tests integration lint help

# Default target
all: deploy

deploy:
	@echo "Deploying eoAPI."
	@command -v bash >/dev/null 2>&1 || { echo "bash is required but not installed"; exit 1; }
	@./scripts/deploy.sh

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
	@./scripts/ingest.sh || { echo "Ingestion failed."; exit 1; }

tests:
	@echo "Running Helm unit tests..."
	@command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed"; exit 1; }
	@./scripts/deploy.sh setup
	@./scripts/test.sh helm

integration:
	@echo "Running integration tests against Kubernetes cluster..."
	@command -v bash >/dev/null 2>&1 || { echo "bash is required but not installed"; exit 1; }
	@./scripts/test.sh integration

lint:
	@echo "Running linting and code quality checks..."
	@if [ ! -f .git/hooks/pre-commit ]; then \
		echo "Installing pre-commit..."; \
		uv pip install pre-commit yamllint shellcheck-py || pip3 install --user pre-commit yamllint shellcheck-py; \
		pre-commit install; \
	fi
	@pre-commit run --all-files

help:
	@echo "Makefile commands:"
	@echo "  make deploy         -  Deploy eoAPI to the configured Kubernetes cluster."
	@echo "  make minikube       -  Install eoAPI on minikube."
	@echo "  make ingest         -  Ingest STAC collections and items into the database."
	@echo "  make integration    -  Run integration tests on connected Kubernetes cluster."
	@echo "  make tests          -  Run lint + unit tests."
	@echo "  make lint           -  Run linting and code quality checks."
	@echo "  make help           -  Show this help message."
