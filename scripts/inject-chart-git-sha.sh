#!/usr/bin/env bash
# Inject the current git commit into eoapi values.yaml for release packaging.
set -euo pipefail

VALUES_YAML="${1:-charts/eoapi/values.yaml}"
SHA=$(git rev-parse HEAD | cut -c1-10)

if [[ ! -f "$VALUES_YAML" ]]; then
  echo "values.yaml not found: $VALUES_YAML" >&2
  exit 1
fi

sed -i "s/^gitSha: \"gitshaABC123\"/gitSha: \"${SHA}\"/" "$VALUES_YAML"

echo "Injected gitSha=${SHA} into ${VALUES_YAML}"
