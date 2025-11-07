# Makefile for eoapi-k8s

# Configuration
CLUSTER_TYPE ?= minikube
NAMESPACE ?= eoapi
RELEASE_NAME ?= eoapi
TIMEOUT ?= 5m

# Script paths
SCRIPTS_DIR := ./scripts
DEPLOY_SCRIPT := $(SCRIPTS_DIR)/deploy.sh
LOCAL_CLUSTER_SCRIPT := $(SCRIPTS_DIR)/local-cluster.sh
TEST_SCRIPT := $(SCRIPTS_DIR)/test.sh

.PHONY: help deploy setup cleanup status info test lint validate docs clean-all
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "eoAPI Kubernetes Makefile"
	@echo ""
	@echo "MAIN COMMANDS:"
	@echo "  deploy          Deploy eoAPI to current kubectl context"
	@echo "  setup           Setup environment and dependencies only"
	@echo "  cleanup         Clean up eoAPI deployment"
	@echo "  status          Show deployment status"
	@echo "  info            Show deployment info and URLs"
	@echo "  validate        Validate deployment health and API connectivity"
	@echo ""
	@echo "TESTING:"
	@echo "  test            Run all tests (lint + helm + integration)"
	@echo "  test-helm       Run Helm tests only"
	@echo "  test-integration Run integration tests only"
	@echo ""
	@echo "LOCAL DEVELOPMENT:"
	@echo "  local           Manage local cluster (create, start, stop, delete, status)"
	@echo "  local-deploy    Create local cluster and deploy eoAPI"
	@echo "  local-test      Run full test suite on local cluster"
	@echo ""
	@echo "QUALITY ASSURANCE:"
	@echo "  lint            Run linting and code quality checks"
	@echo "  validate        Validate Helm charts and schemas"
	@echo ""
	@echo "DOCUMENTATION:"
	@echo "  docs            Generate documentation package"
	@echo "  serve-docs      Serve docs locally at http://localhost:8000"
	@echo ""
	@echo "CLEANUP:"
	@echo "  clean-all       Clean deployment + local cluster"
	@echo ""
	@echo "VARIABLES:"
	@echo "  CLUSTER_TYPE    Local cluster type: minikube or k3s (default: minikube)"
	@echo "  NAMESPACE       Target namespace (default: eoapi)"
	@echo "  RELEASE_NAME    Helm release name (default: eoapi)"
	@echo "  TIMEOUT         Operation timeout (default: 10m)"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make deploy NAMESPACE=prod"
	@echo "  make local CLUSTER_TYPE=k3s"
	@echo "  make test-integration"

# Core deployment commands
deploy: ## Deploy eoAPI to current cluster
	@$(DEPLOY_SCRIPT) deploy --namespace $(NAMESPACE) --release $(RELEASE_NAME) --timeout $(TIMEOUT)

setup: ## Setup environment and dependencies
	@$(DEPLOY_SCRIPT) setup --namespace $(NAMESPACE) --timeout $(TIMEOUT)

cleanup: ## Clean up eoAPI deployment
	@$(DEPLOY_SCRIPT) cleanup --namespace $(NAMESPACE) --release $(RELEASE_NAME)

status: ## Show deployment status
	@$(DEPLOY_SCRIPT) status --namespace $(NAMESPACE) --release $(RELEASE_NAME)

info: ## Show deployment information and URLs
	@$(DEPLOY_SCRIPT) info --namespace $(NAMESPACE) --release $(RELEASE_NAME)

validate: ## Validate deployment health and API connectivity
	@$(DEPLOY_SCRIPT) validate --namespace $(NAMESPACE) --release $(RELEASE_NAME) --verbose

# Testing commands
test: lint test-helm test-integration ## Run all tests

test-helm: ## Run Helm tests only
	@$(TEST_SCRIPT) helm

test-integration: ## Run integration tests only
	@NAMESPACE=$(NAMESPACE) $(TEST_SCRIPT) integration

# Local development - unified command with subcommands
local: ## Manage local cluster (usage: make local ACTION=create|start|stop|delete|status)
	@$(LOCAL_CLUSTER_SCRIPT) $(ACTION) --type $(CLUSTER_TYPE)

local-create: ## Create and start local cluster
	@$(LOCAL_CLUSTER_SCRIPT) create --type $(CLUSTER_TYPE)

local-start: ## Start existing local cluster
	@$(LOCAL_CLUSTER_SCRIPT) start --type $(CLUSTER_TYPE)

local-stop: ## Stop local cluster
	@$(LOCAL_CLUSTER_SCRIPT) stop --type $(CLUSTER_TYPE)

local-delete: ## Delete local cluster
	@$(LOCAL_CLUSTER_SCRIPT) delete --type $(CLUSTER_TYPE)

local-status: ## Show local cluster status
	@$(LOCAL_CLUSTER_SCRIPT) status --type $(CLUSTER_TYPE)

local-deploy: local-create deploy ## Create local cluster and deploy eoAPI

local-test: ## Run full test suite on local cluster
	@$(LOCAL_CLUSTER_SCRIPT) start --type $(CLUSTER_TYPE)
	@$(LOCAL_CLUSTER_SCRIPT) context --type $(CLUSTER_TYPE)
	@$(MAKE) test

# Quality assurance
lint: ## Run linting and code quality checks
	@echo "🔍 Running code quality checks..."
	@if [ ! -f .git/hooks/pre-commit ]; then \
		echo "Installing pre-commit hooks..."; \
		command -v uv >/dev/null 2>&1 && uv pip install pre-commit yamllint shellcheck-py || \
		pip3 install --user pre-commit yamllint shellcheck-py; \
		pre-commit install; \
	fi
	@pre-commit run --all-files

validate: ## Validate Helm charts and schemas
	@echo "🔍 Validating Helm charts..."
	@command -v helm >/dev/null 2>&1 || { echo "❌ helm required but not installed"; exit 1; }
	@for chart_dir in charts/*/; do \
		if [ -d "$$chart_dir" ]; then \
			chart_name=$$(basename "$$chart_dir"); \
			echo "Validating $$chart_name..."; \
			if ! helm lint "$$chart_dir" --strict; then \
				echo "❌ $$chart_name lint failed"; \
				exit 1; \
			fi; \
			if ! helm template test "$$chart_dir" --debug --dry-run >/dev/null; then \
				echo "❌ $$chart_name template failed"; \
				exit 1; \
			fi; \
			echo "✅ $$chart_name validation passed"; \
		fi; \
	done

validate-schema: validate ## Validate JSON schemas (requires ajv-cli)
	@echo "🔍 Validating JSON schemas..."
	@command -v ajv >/dev/null 2>&1 || { echo "❌ ajv-cli required. Run: npm install -g ajv-cli ajv-formats"; exit 1; }
	@for chart_dir in charts/*/; do \
		chart_name=$$(basename "$$chart_dir"); \
		if [ -f "$${chart_dir}values.schema.json" ]; then \
			echo "🔍 Validating $$chart_name schema..."; \
			if ! ajv compile -s "$${chart_dir}values.schema.json" --spec=draft7 --strict=false; then \
				echo "❌ $$chart_name schema compilation failed"; \
				exit 1; \
			fi; \
			if ! python3 -c "import yaml,json; json.dump(yaml.safe_load(open('$${chart_dir}values.yaml')), open('/tmp/values-$${chart_name}.json','w'))"; then \
				echo "❌ $$chart_name values parsing failed"; \
				rm -f "/tmp/values-$${chart_name}.json"; \
				exit 1; \
			fi; \
			if ! ajv validate -s "$${chart_dir}values.schema.json" -d "/tmp/values-$${chart_name}.json" --spec=draft7; then \
				echo "❌ $$chart_name schema validation failed"; \
				rm -f "/tmp/values-$${chart_name}.json"; \
				exit 1; \
			fi; \
			rm -f "/tmp/values-$${chart_name}.json"; \
			echo "✅ $$chart_name schema validation passed"; \
		else \
			echo "⚠️ $$chart_name: no values.schema.json found, skipping"; \
		fi; \
	done

# Documentation
docs: ## Generate documentation package
	@echo "📚 Building documentation..."
	@command -v mkdocs >/dev/null 2>&1 || { echo "❌ mkdocs required. Run: pip install mkdocs-material"; exit 1; }
	@mkdocs build

serve-docs: ## Serve documentation locally
	@echo "📚 Serving docs at http://localhost:8000"
	@echo "Press Ctrl+C to stop"
	@command -v mkdocs >/dev/null 2>&1 || { echo "❌ mkdocs required. Run: pip install mkdocs-material"; exit 1; }
	@mkdocs serve --dev-addr localhost:8000

# Data ingestion (legacy compatibility)
ingest: ## Ingest sample data (legacy command)
	@$(SCRIPTS_DIR)/ingest.sh

# Cleanup commands
clean-all: cleanup local-delete ## Clean deployment and delete local cluster

# Development utilities
debug: ## Show debug information about deployment
	@$(SCRIPTS_DIR)/debug-deployment.sh

check-tools: ## Check if required tools are installed
	@echo "🔍 Checking required tools..."
	@$(TEST_SCRIPT) check-deps

# Build targets for charts
charts/*/Chart.lock: charts/*/Chart.yaml
	@chart_dir=$(dir $@); \
	echo "Updating dependencies for $$(basename $$chart_dir)..."; \
	helm dependency build $$chart_dir

dependency-update: charts/*/Chart.lock ## Update all chart dependencies

# Help target that extracts help from comments
help-verbose: ## Show detailed help with all available targets
	@echo "eoAPI Kubernetes Makefile - All Available Targets"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
