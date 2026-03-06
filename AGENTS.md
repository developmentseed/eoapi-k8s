# AGENTS.md

## Coding principles

- Write high quality code, look always at the bigger picture: concise changes, no bloat
- Think test-driven; add/update tests for every change
- Commits use [Conventional Commits](https://www.conventionalcommits.org/) titles

## Project structure

- `charts/eoapi/` — main Helm chart (primary codebase)
  - `values.yaml` — source of truth for all config; `values.schema.json` validates it
  - `templates/_helpers/` — named template library (core, services, database, resources, validation)
  - `profiles/` — layered value overlays: `core.yaml`, `production.yaml`, `experimental.yaml`, `local/`
  - `tests/` — `helm-unittest` suites; snapshots in `__snapshot__/` are committed
- `tests/integration/` — pytest integration tests (require live cluster); fixtures in `conftest.py`
- `scripts/` — `eoapi-cli` implementation; see `scripts/README.md` for full CLI reference
- `docs/` — MkDocs source
- `.github/workflows/` — CI: fast checks (no cluster) → integration tests (k3s)

## Testing workflow

```bash
# No cluster needed (run these first)
./eoapi-cli test schema      # Validate values.schema.json
./eoapi-cli test lint        # helm lint
./eoapi-cli test unit        # helm-unittest (plugin must be installed separately)
./eoapi-cli test images      # Check no container runs as root

# Requires a cluster
./eoapi-cli cluster start && ./eoapi-cli deployment run && ./eoapi-cli test integration --debug
./eoapi-cli deployment run && ./eoapi-cli test integration --debug   # existing k3s
./eoapi-cli test all --debug
./eoapi-cli test integration --pytest-args="-v -k test_stac"

# After intentional template changes, regenerate snapshots
helm unittest charts/eoapi -u   # then commit __snapshot__/
```

## Non-obvious gotchas

- `gitSha` is a **required** value on every install/upgrade: `--set gitSha=$(git rev-parse HEAD | cut -c1-10)`
- External DB requires `postgrescluster.enabled: false` alongside `postgresql.type: external-*`
- ArgoCD deployments need hook annotations translated from `helm.sh/hook` to `argocd.argoproj.io/hook`; use `charts/eoapi/values/argocd.yaml`
- Profiles layer on top of `values.yaml`; later `-f` files win

## Where to read more

- `README.md` — project overview and prerequisites
- `scripts/README.md` — full `eoapi-cli` command reference and environment variables
- `docs/quick-start.md` — fastest path to a running deployment
- `docs/configuration.md` — complete `values.yaml` reference (DB types, services, ingress, autoscaling, resources)
- `docs/helm-install.md` — manual step-by-step Helm install
- `docs/release.md` — release and versioning process
- `docs/argocd.md` — ArgoCD sync waves and hook configuration
- `docs/autoscaling.md` — HPA setup with Prometheus adapter
- `docs/observability.md` — Prometheus + Grafana stack
- `docs/stac-auth-proxy.md` — OIDC authentication proxy
- `docs/unified-ingress.md` — NGINX/Traefik ingress setup
- `docs/aws-eks.md`, `docs/gcp-gke.md`, `docs/azure.md` — cloud-provider-specific guides
- `charts/eoapi/profiles/README.md` — when to use each profile
