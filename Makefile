# Makefile for eoapi-k8s

LOCAL_CLUSTER_SCRIPT := ./scripts/local-cluster.sh
DEPLOY_SCRIPT := ./scripts/deploy.sh
TEST_SCRIPT := ./scripts/test.sh

# Default cluster type (can be overridden)
CLUSTER_TYPE ?= minikube

.PHONY: help deploy clean tests integration lint validate-schema docs serve-docs
.DEFAULT_GOAL := help

help:
	@echo "eoAPI Kubernetes Makefile"
	@echo ""
	@echo "MAIN COMMANDS:"
	@echo "  deploy          Deploy eoAPI to current kubectl context"
	@echo "  tests           Run Helm unit tests"
	@echo "  integration     Run integration tests on current cluster"
	@echo "  clean           Clean up deployment"
	@echo ""
	@echo "LOCAL DEVELOPMENT:"
	@echo "  local           Create local cluster and deploy (CLUSTER_TYPE=minikube|k3s)"
	@echo "  local-start     Start existing local cluster"
	@echo "  local-stop      Stop local cluster"
	@echo "  local-delete    Delete local cluster"
	@echo "  local-status    Show local cluster status"
	@echo "  test-local      Run full integration tests on local cluster"
	@echo ""
	@echo "QUALITY:"
	@echo "  lint            Run linting and code quality checks"
	@echo "  validate-schema Validate Helm schemas"
	@echo "  docs            Generate portable documentation package"
	@echo "  serve-docs      Serve docs with mkdocs at http://localhost:8000"
	@echo ""
	@echo "VARIABLES:"
	@echo "  CLUSTER_TYPE    Local cluster type: minikube or k3s (default: minikube)"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make local CLUSTER_TYPE=minikube"
	@echo "  make test-local CLUSTER_TYPE=k3s"

deploy:
	@$(DEPLOY_SCRIPT)

clean:
	@$(DEPLOY_SCRIPT) cleanup

tests:
	@$(DEPLOY_SCRIPT) setup
	@$(TEST_SCRIPT) helm

integration:
	@$(TEST_SCRIPT) integration

local:
	@$(LOCAL_CLUSTER_SCRIPT) deploy --type $(CLUSTER_TYPE)

local-start:
	@$(LOCAL_CLUSTER_SCRIPT) start --type $(CLUSTER_TYPE)

local-stop:
	@$(LOCAL_CLUSTER_SCRIPT) stop --type $(CLUSTER_TYPE)

local-delete:
	@$(LOCAL_CLUSTER_SCRIPT) delete --type $(CLUSTER_TYPE)

local-status:
	@$(LOCAL_CLUSTER_SCRIPT) status --type $(CLUSTER_TYPE)

test-local:
	@$(LOCAL_CLUSTER_SCRIPT) start --type $(CLUSTER_TYPE)
	@$(LOCAL_CLUSTER_SCRIPT) context --type $(CLUSTER_TYPE)
	@$(MAKE) integration

lint:
	@if [ ! -f .git/hooks/pre-commit ]; then \
		echo "Installing pre-commit..."; \
		uv pip install pre-commit yamllint shellcheck-py || pip3 install --user pre-commit yamllint shellcheck-py; \
		pre-commit install; \
	fi
	@pre-commit run --all-files

validate-schema:
	@command -v helm >/dev/null 2>&1 || { echo "❌ helm required but not installed"; exit 1; }
	@command -v ajv >/dev/null 2>&1 || { echo "❌ ajv-cli required. Run: npm install -g ajv-cli ajv-formats"; exit 1; }
	@for chart_dir in charts/*/; do \
		chart_name=$$(basename "$$chart_dir"); \
		if [ -f "$${chart_dir}values.schema.json" ]; then \
			echo "🔍 Validating $$chart_name..."; \
			helm lint "$$chart_dir" --strict && \
			helm template test "$$chart_dir" >/dev/null && \
			ajv compile -s "$${chart_dir}values.schema.json" --spec=draft7 --strict=false && \
			python3 -c "import yaml,json; json.dump(yaml.safe_load(open('$${chart_dir}values.yaml')), open('/tmp/values-$${chart_name}.json','w'))" && \
			ajv validate -s "$${chart_dir}values.schema.json" -d "/tmp/values-$${chart_name}.json" --spec=draft7 && \
			rm -f "/tmp/values-$${chart_name}.json" && \
			echo "✅ $$chart_name validation passed" || { \
				rm -f "/tmp/values-$${chart_name}.json"; \
				echo "❌ $$chart_name validation failed"; \
				exit 1; \
			}; \
		else \
			echo "⚠️ $$chart_name: no values.schema.json found, skipping"; \
		fi; \
	done

ingest:
	@./scripts/ingest.sh

docs:
	@command -v mkdocs >/dev/null 2>&1 || { echo "❌ mkdocs required. Run: pip install mkdocs-material"; exit 1; }
	@echo "📚 Building documentation with mkdocs"
	@mkdocs build

serve-docs: docs
	@echo "📚 Serving docs with mkdocs at http://localhost:8000"
	@echo "Press Ctrl+C to stop"
	@mkdocs serve --dev-addr localhost:8000
