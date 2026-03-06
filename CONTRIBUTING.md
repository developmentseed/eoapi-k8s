# Contributing

We welcome contributions to eoapi-k8s! All contributions are reviewed and must follow our project guidelines.

## Getting Started

Before contributing, please:

1. Read [`README.md`](README.md), [`AGENTS.md`](AGENTS.md) and [docs](docs) for project structure and coding principles
2. Check existing [issues](https://github.com/developmentseed/eoapi-k8s/issues) and [pull requests](https://github.com/developmentseed/eoapi-k8s/pulls)

## Development Workflow

### Prerequisites

- Kubernetes cluster (local k3d/k3s or cloud-based)
- [Helm 3.x](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for your cluster
- [helm-unittest](https://github.com/helm-unittest/helm-unittest?tab=readme-ov-file#install) plugin for running unit tests

### Quick Start

```bash
# Clone the repository
git clone https://github.com/developmentseed/eoapi-k8s.git
cd eoapi-k8s

# Run fast checks (no cluster needed)
./eoapi-cli test schema
./eoapi-cli test lint
./eoapi-cli test unit

# Start local cluster and run integration tests
./eoapi-cli cluster start
./eoapi-cli deployment run
./eoapi-cli test integration --debug

# Cleanup
./eoapi-cli cluster clean
```

### Key Commands

- `./eoapi-cli test all` — Run all test suites
- `./eoapi-cli test schema` — Validate values.schema.json
- `./eoapi-cli test lint` — Run Helm lint
- `./eoapi-cli test unit` — Run Helm unit tests
- `./eoapi-cli test integration` — Run integration tests (requires cluster)
- `./eoapi-cli deployment debug` — Debug failed deployments
- `helm unittest charts/eoapi -u` — Update test snapshots

See [`scripts/README.md`](scripts/README.md) for the complete CLI reference.

## Pull Request Guidelines

### Before Submitting

1. **Test thoroughly**
   - Run `./eoapi-cli test all` successfully
   - Test on a real cluster (local k3d or cloud)
   - Update test snapshots if you changed templates: `helm unittest charts/eoapi -u`

2. **Update documentation**
   - Add/update relevant documentation in `docs/`
   - Update [`CHANGELOG.md`](CHANGELOG.md) under the "Unreleased" section

3. **Follow conventions**
   - Keep code concise and high quality
   - Add unit tests for template changes in `charts/eoapi/tests/`
   - Add integration tests for feature changes in `tests/integration/`

### PR Title Format

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `test:` — Adding/updating tests
- `refactor:` — Code refactoring
- `chore:` — Maintenance tasks

**Examples:**
- `feat: add support for external Redis cache`
- `fix: correct pgSTAC migration job ordering`
- `docs: clarify ArgoCD sync wave configuration`

### PR Description

Write clear, concise descriptions in your own words:

- **What** does this PR do?
- **Why** is this change needed?
- **How** was it tested?
- Link to related issues: `Fixes #123` or `Relates to #456`

## AI Use Policy

AI tools are part of modern development workflows and contributors may use them. However, all contributions must meet eoapi-k8s quality standards regardless of how they were created.

### Guidelines

AI-assisted development is acceptable when used responsibly. Contributors must:

- **Test all code thoroughly.** Submit only code you have verified works correctly on a real cluster.
- **Understand your contributions.** You must be able to explain Helm templates, Kubernetes resources, and bash scripts you submit.
- **Write clear, concise PR descriptions** in your own words.
- **Use your own voice** in GitHub issues and PR discussions.
- **Take responsibility** for code quality, correctness, and maintainability.

### Disclosure

Disclose AI assistance when substantial template logic or bash scripts were AI-generated, or when uncertain about licensing or copyright implications. Be honest if a reviewer asks about code origins.

### Unacceptable Submissions

Pull requests may be closed without review if they contain:

- Untested code
- Verbose AI-generated descriptions
- Evidence the contributor doesn't understand the submission
- Broken deployments or failing tests

Using AI to assist learning and development is encouraged. Using it to bypass understanding or submit work you cannot explain is not.

*This policy is adapted from the [GRASS GIS contribution guidelines](https://github.com/OSGeo/grass/blob/main/CONTRIBUTING.md).*

## Getting Help

- **Questions?** Open a [discussion](https://github.com/developmentseed/eoAPI/discussions)
- **Found a bug?** Open an [issue](https://github.com/developmentseed/eoapi-k8s/issues)
- **Need professional support?** Email eoapi@developmentseed.org

Thank you for contributing to eoapi-k8s! 🚀
