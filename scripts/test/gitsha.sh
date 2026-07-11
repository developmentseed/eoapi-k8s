#!/usr/bin/env bash

# Verify inject-chart-git-sha.sh replaces the placeholder in values.yaml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

VALUES_SRC="${PROJECT_ROOT}/charts/eoapi/values.yaml"
INJECT_SCRIPT="${PROJECT_ROOT}/scripts/inject-chart-git-sha.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

tmp_values="${tmpdir}/values.yaml"
cp "$VALUES_SRC" "$tmp_values"

if ! grep -q '^gitSha: "gitshaABC123"' "$tmp_values"; then
  log_error "Expected gitSha placeholder in ${VALUES_SRC}"
  exit 1
fi

expected_sha=$(git -C "$PROJECT_ROOT" rev-parse HEAD | cut -c1-10)

bash "$INJECT_SCRIPT" "$tmp_values"

if grep -q "^gitSha: \"${expected_sha}\"" "$tmp_values"; then
  log_success "gitSha injection replaced placeholder with ${expected_sha}"
  exit 0
fi

log_error "Expected gitSha: \"${expected_sha}\" after injection, got:"
grep '^gitSha:' "$tmp_values" || true
exit 1
