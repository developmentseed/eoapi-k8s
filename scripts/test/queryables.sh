#!/usr/bin/env bash

# Verify the rendered pgstac-load-queryables script passes the expected argv
# to pypgstac when executed by sh (catches shell-level breakage helm-unittest can't).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

CHART_PATH="${PROJECT_ROOT}/charts/eoapi"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "${tmpdir}/values.yaml" <<'EOF'
pgstacBootstrap:
  settings:
    queryables:
      - name: q.json
        configMapRef: { name: my-queryables, key: queryables.json }
        collections: ["openaerialmap", "it's a test"]
        indexFields: ["oam:owner_id"]
        deleteMissing: true
EOF

helm template eoapi "$CHART_PATH" -f "${tmpdir}/values.yaml" \
  --show-only templates/database/pgstacbootstrap/job.yaml \
  | yq -r 'select(.metadata.name == "eoapi-pgstac-load-queryables") | .spec.template.spec.containers[0].args[0]' \
  > "${tmpdir}/script.sh"

# Stub pypgstac: record each load-queryables argument on its own line.
mkdir -p "${tmpdir}/bin"
cat > "${tmpdir}/bin/pypgstac" <<EOF
#!/bin/sh
[ "\$1" = "pgready" ] && exit 0
printf '%s\n' "\$@" >> "${tmpdir}/argv"
EOF
chmod +x "${tmpdir}/bin/pypgstac"

if ! PATH="${tmpdir}/bin:${PATH}" sh "${tmpdir}/script.sh" > "${tmpdir}/out" 2>&1; then
  log_error "Rendered load-queryables script failed:"
  cat "${tmpdir}/out"
  exit 1
fi

expected=$(cat <<'EOF'
load-queryables
--delete-missing
--collection-ids
["openaerialmap","it's a test"]
--index-fields
["oam:owner_id"]
/opt/queryables/q.json
EOF
)

actual=$(cat "${tmpdir}/argv" 2>/dev/null || true)

if [[ "$actual" == "$expected" ]]; then
  log_success "load-queryables received the expected arguments"
  exit 0
fi

log_error "Unexpected load-queryables arguments. Expected:"
echo "$expected"
log_error "Got:"
echo "$actual"
exit 1
